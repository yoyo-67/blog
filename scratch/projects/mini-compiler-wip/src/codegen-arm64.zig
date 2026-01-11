const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const zir_mod = @import("zir.zig");
const ast_mod = @import("ast.zig");
const sema_mod = @import("sema.zig");
const lower_mod = @import("lower.zig");
const Operand = lower_mod.Operand;
const LoweredInst = lower_mod.LoweredInst;
const LoweredFunction = lower_mod.LoweredFunction;

const Gen = @This();

// ============================================================================
// ARM64 Register Conventions
// ============================================================================

const Reg = struct {
    /// Parameter/return registers (caller-saved)
    const arg0: u8 = 0; // w0 - first arg and return value
    const arg1: u8 = 1; // w1
    const arg2: u8 = 2; // w2
    const arg3: u8 = 3; // w3
    const arg4: u8 = 4; // w4
    const arg5: u8 = 5; // w5
    const arg6: u8 = 6; // w6
    const arg7: u8 = 7; // w7

    /// Temporary registers for intermediate values (caller-saved)
    const temp_start: u8 = 8; // w8-w15
    const temp_end: u8 = 15;
    const temp_count: u8 = temp_end - temp_start + 1;

    /// Scratch registers for materialization
    const scratch0: u8 = 16; // w16 - for LHS operand
    const scratch1: u8 = 17; // w17 - for RHS operand
};

// ============================================================================
// Generator State
// ============================================================================

output: std.ArrayListUnmanaged(u8),
allocator: Allocator,
/// Maps instruction index -> register where result lives
locs: [256]u8,

pub fn init(allocator: Allocator) Gen {
    return .{
        .output = .empty,
        .allocator = allocator,
        .locs = undefined,
    };
}

// ============================================================================
// Public API
// ============================================================================

pub fn generate(self: *Gen, program: zir_mod.Program) ![]const u8 {
    for (program.functions()) |function| {
        const sema_result = try sema_mod.analyzeFunction(self.allocator, function);
        const lowered = try lower_mod.lower(self.allocator, sema_result.function);
        try self.emitFunction(lowered);
        try self.write("\n");
    }
    return self.output.toOwnedSlice(self.allocator);
}

pub fn generateSingleFunction(self: *Gen, function: zir_mod.Function) ![]const u8 {
    const sema_result = try sema_mod.analyzeFunction(self.allocator, function);
    const lowered = try lower_mod.lower(self.allocator, sema_result.function);
    try self.emitFunction(lowered);
    return self.output.toOwnedSlice(self.allocator);
}

// ============================================================================
// Function Emission
// ============================================================================

fn emitFunction(self: *Gen, function: LoweredFunction) !void {
    try self.emitGlobal(function.name);
    try self.emitLabel(function.name);
    try self.emitPrologue();

    for (function.instructions, 0..) |inst, idx| {
        try self.emitInstruction(inst, @intCast(idx));
    }
}

fn emitPrologue(self: *Gen) !void {
    try self.emitInstr("stp", "x29, x30, [sp, #-16]!", .{});
    try self.emitInstr("mov", "x29, sp", .{});
}

fn emitEpilogue(self: *Gen) !void {
    try self.emitInstr("ldp", "x29, x30, [sp], #16", .{});
    try self.emitInstr("ret", "", .{});
}

// ============================================================================
// Instruction Emission - just iterate and emit!
// ============================================================================

fn emitInstruction(self: *Gen, inst: LoweredInst, idx: u32) !void {
    switch (inst) {
        .add => |op| try self.emitBinaryOp(idx, "add", op.lhs, op.rhs, true),
        .sub => |op| try self.emitBinaryOp(idx, "sub", op.lhs, op.rhs, true),
        .mul => |op| try self.emitBinaryOp(idx, "mul", op.lhs, op.rhs, false),
        .div => |op| try self.emitBinaryOp(idx, "sdiv", op.lhs, op.rhs, false),
        .ret => |op| try self.emitReturn(op),
        .call => |c| try self.emitCall(idx, c.name, c.args),
    }
}

fn emitBinaryOp(self: *Gen, idx: u32, mnemonic: []const u8, lhs: Operand, rhs: Operand, imm_rhs_ok: bool) !void {
    const dest = self.allocTempReg(idx);
    self.locs[idx] = dest;

    // LHS must be in register
    const lhs_reg = try self.materialize(lhs, Reg.scratch0);

    // RHS can be immediate for add/sub
    if (imm_rhs_ok and rhs == .imm) {
        try self.emitInstr(mnemonic, "w{d}, w{d}, #{d}", .{ dest, lhs_reg, rhs.imm });
    } else {
        const rhs_reg = try self.materialize(rhs, Reg.scratch1);
        try self.emitInstr(mnemonic, "w{d}, w{d}, w{d}", .{ dest, lhs_reg, rhs_reg });
    }
}

fn emitReturn(self: *Gen, op: Operand) !void {
    try self.moveToReg(Reg.arg0, op);
    try self.emitEpilogue();
}

fn emitCall(self: *Gen, idx: u32, name: []const u8, args: []const Operand) !void {
    // Move args to arg registers
    for (args, 0..) |arg, i| {
        try self.moveToReg(@intCast(i), arg);
    }

    try self.emitInstr("bl", "_{s}", .{name});

    // Save return value (w0) to temp register
    const dest = self.allocTempReg(idx);
    self.locs[idx] = dest;
    try self.emitMov(dest, Reg.arg0);
}

// ============================================================================
// Register Allocation
// ============================================================================

fn allocTempReg(self: *Gen, idx: u32) u8 {
    _ = self;
    return Reg.temp_start + @as(u8, @intCast(idx % Reg.temp_count));
}

/// Get register for operand; load immediate into scratch if needed
fn materialize(self: *Gen, op: Operand, scratch: u8) !u8 {
    return switch (op) {
        .imm => |v| {
            try self.emitInstr("mov", "w{d}, #{d}", .{ scratch, v });
            return scratch;
        },
        .param => |i| i, // params are in w0-w7
        .inst => |i| self.locs[i], // look up where instruction result lives
    };
}

/// Move operand to specific register
fn moveToReg(self: *Gen, dest: u8, op: Operand) !void {
    switch (op) {
        .imm => |v| try self.emitInstr("mov", "w{d}, #{d}", .{ dest, v }),
        .param => |i| if (i != dest) try self.emitInstr("mov", "w{d}, w{d}", .{ dest, i }),
        .inst => |i| {
            const src = self.locs[i];
            if (src != dest) try self.emitInstr("mov", "w{d}, w{d}", .{ dest, src });
        },
    }
}

// ============================================================================
// Code Emission
// ============================================================================

fn emitGlobal(self: *Gen, name: []const u8) !void {
    try std.fmt.format(self.writer(), ".global _{s}\n", .{name});
}

fn emitLabel(self: *Gen, name: []const u8) !void {
    try std.fmt.format(self.writer(), "_{s}:\n", .{name});
}

fn emitMov(self: *Gen, dst: u8, src: u8) !void {
    if (dst != src) {
        try self.emitInstr("mov", "w{d}, w{d}", .{ dst, src });
    }
}

fn emitInstr(self: *Gen, mnemonic: []const u8, comptime operands_fmt: []const u8, args: anytype) !void {
    try self.write("    ");
    try self.write(mnemonic);
    if (operands_fmt.len > 0) {
        try self.write(" ");
        try std.fmt.format(self.writer(), operands_fmt, args);
    }
    try self.write("\n");
}

fn write(self: *Gen, str: []const u8) !void {
    try self.output.appendSlice(self.allocator, str);
}

fn writer(self: *Gen) std.ArrayListUnmanaged(u8).Writer {
    return self.output.writer(self.allocator);
}

// ============================================================================
// Tests
// ============================================================================

fn testGenerate(input: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);

    var gen = Gen.init(allocator);
    const result = try gen.generate(program);

    const copy = try testing.allocator.alloc(u8, result.len);
    @memcpy(copy, result);
    return copy;
}

test "simple return constant" {
    const result = try testGenerate("fn main() i32 { return 42; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _main
        \\_main:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w0, #42
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "return with arithmetic" {
    const result = try testGenerate("fn calc() i32 { return 1 + 2; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _calc
        \\_calc:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w16, #1
        \\    add w8, w16, #2
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function with parameter" {
    const result = try testGenerate("fn square(x: i32) i32 { return x * x; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _square
        \\_square:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mul w8, w0, w0
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function with two parameters" {
    const result = try testGenerate("fn add(a: i32, b: i32) i32 { return a + b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _add
        \\_add:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    add w8, w0, w1
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "subtraction" {
    const result = try testGenerate("fn sub(a: i32, b: i32) i32 { return a - b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _sub
        \\_sub:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    sub w8, w0, w1
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "division" {
    const result = try testGenerate("fn div(a: i32, b: i32) i32 { return a / b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _div
        \\_div:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    sdiv w8, w0, w1
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "variable declaration and use" {
    const result = try testGenerate(
        \\fn foo() i32 {
        \\  const x = 10;
        \\  return x;
        \\}
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _foo
        \\_foo:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w0, #10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function call no args" {
    const result = try testGenerate(
        \\fn foo() i32 { return 42; }
        \\fn main() i32 { return foo(); }
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _foo
        \\_foo:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w0, #42
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\.global _main
        \\_main:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    bl _foo
        \\    mov w8, w0
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function call with args" {
    const result = try testGenerate(
        \\fn add(a: i32, b: i32) i32 { return a + b; }
        \\fn main() i32 { return add(3, 5); }
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _add
        \\_add:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    add w8, w0, w1
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\.global _main
        \\_main:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w0, #3
        \\    mov w1, #5
        \\    bl _add
        \\    mov w8, w0
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}
