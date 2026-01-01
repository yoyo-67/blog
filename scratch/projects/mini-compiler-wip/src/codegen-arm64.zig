const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const zir_mod = @import("zir.zig");
const ast_mod = @import("ast.zig");
const Value = @import("types.zig").Value;

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

    fn isArgReg(r: u8) bool {
        return r <= arg7;
    }

    fn isTempReg(r: u8) bool {
        return r >= temp_start and r <= temp_end;
    }
};

// ============================================================================
// Operand - Value Location
// ============================================================================

const Operand = union(enum) {
    imm: i64,
    reg: u8,

    fn isImm(self: Operand) bool {
        return self == .imm;
    }

    fn isReg(self: Operand) bool {
        return self == .reg;
    }

    fn inReg(r: u8) Operand {
        return .{ .reg = r };
    }

    fn immediate(v: i64) Operand {
        return .{ .imm = v };
    }
};

// ============================================================================
// Generator State
// ============================================================================

output: std.ArrayListUnmanaged(u8),
allocator: Allocator,
values: std.AutoHashMap(u32, Operand),

pub fn init(allocator: Allocator) Gen {
    return .{
        .output = .empty,
        .allocator = allocator,
        .values = std.AutoHashMap(u32, Operand).init(allocator),
    };
}

pub fn deinit(self: *Gen) void {
    self.values.deinit();
}

// ============================================================================
// Public API
// ============================================================================

pub fn generate(self: *Gen, program: zir_mod.Program) ![]const u8 {
    for (program.functions()) |function| {
        try self.generateFunction(function);
        try self.write("\n");
    }
    return self.output.toOwnedSlice(self.allocator);
}

pub fn generateSingleFunction(self: *Gen, function: zir_mod.Function) ![]const u8 {
    try self.generateFunction(function);
    return self.output.toOwnedSlice(self.allocator);
}

// ============================================================================
// Function Generation
// ============================================================================

fn generateFunction(self: *Gen, function: zir_mod.Function) !void {
    self.values.clearRetainingCapacity();

    try self.emitGlobal(function.name);
    try self.emitLabel(function.name);
    try self.emitPrologue();

    for (function.instructions(), 0..) |inst, idx| {
        try self.generateInstruction(inst, @intCast(idx), function);
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
// Instruction Generation
// ============================================================================

fn generateInstruction(self: *Gen, inst: zir_mod.Instruction, idx: u32, function: zir_mod.Function) !void {
    switch (inst) {
        .literal => |lit| try self.genLiteral(idx, lit.value),
        .param_ref => |ref| try self.genParamRef(idx, ref.value),
        .decl => |decl| try self.genDecl(idx, decl.value),
        .decl_ref => |ref| try self.genDeclRef(idx, ref.name, function),
        .add => |op| try self.genBinaryOp(idx, .add, op.lhs, op.rhs),
        .sub => |op| try self.genBinaryOp(idx, .sub, op.lhs, op.rhs),
        .mul => |op| try self.genBinaryOp(idx, .mul, op.lhs, op.rhs),
        .div => |op| try self.genBinaryOp(idx, .div, op.lhs, op.rhs),
        .return_stmt => |ret| try self.genReturn(ret.value),
        .call => |call| try self.genCall(idx, call.name, call.args),
    }
}

fn genLiteral(self: *Gen, idx: u32, value: Value) !void {
    const val: i64 = switch (value) {
        .int => |v| v,
        .float => |v| @intFromFloat(v),
        .boolean => |v| if (v) 1 else 0,
    };
    try self.values.put(idx, Operand.immediate(val));
}

fn genParamRef(self: *Gen, idx: u32, param_idx: u32) !void {
    // Parameters live in w0-w7 per ARM64 calling convention
    std.debug.assert(param_idx <= Reg.arg7);
    try self.values.put(idx, Operand.inReg(@intCast(param_idx)));
}

fn genDecl(self: *Gen, idx: u32, value_ref: u32) !void {
    const source = self.values.get(value_ref) orelse unreachable;
    try self.values.put(idx, source);
}

fn genDeclRef(self: *Gen, idx: u32, name: []const u8, function: zir_mod.Function) !void {
    if (self.findDecl(function, name, idx)) |decl_value_ref| {
        const source = self.values.get(decl_value_ref) orelse unreachable;
        try self.values.put(idx, source);
    }
}

const BinaryOp = enum {
    add,
    sub,
    mul,
    div,

    fn mnemonic(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "add",
            .sub => "sub",
            .mul => "mul",
            .div => "sdiv",
        };
    }

    /// add/sub can use immediate as RHS operand
    fn supportsImmediateRhs(self: BinaryOp) bool {
        return switch (self) {
            .add, .sub => true,
            .mul, .div => false,
        };
    }
};

fn genBinaryOp(self: *Gen, idx: u32, op: BinaryOp, lhs_ref: u32, rhs_ref: u32) !void {
    const dest = self.allocTempReg(idx);
    const lhs = self.values.get(lhs_ref) orelse unreachable;
    const rhs = self.values.get(rhs_ref) orelse unreachable;

    // LHS must always be in a register
    const lhs_reg = try self.materialize(lhs, Reg.scratch0);

    if (op.supportsImmediateRhs() and rhs.isImm()) {
        try self.emitInstr(op.mnemonic(), "w{d}, w{d}, #{d}", .{ dest, lhs_reg, rhs.imm });
    } else {
        const rhs_reg = try self.materialize(rhs, Reg.scratch1);
        try self.emitInstr(op.mnemonic(), "w{d}, w{d}, w{d}", .{ dest, lhs_reg, rhs_reg });
    }

    try self.values.put(idx, Operand.inReg(dest));
}

fn genReturn(self: *Gen, value_ref: u32) !void {
    const value = self.values.get(value_ref) orelse unreachable;
    try self.moveToReg(Reg.arg0, value);
    try self.emitEpilogue();
}

fn genCall(self: *Gen, idx: u32, name: []const u8, args: []const u32) !void {
    // Move arguments to arg registers (w0-w7)
    for (args, 0..) |arg_ref, i| {
        const arg = self.values.get(arg_ref) orelse unreachable;
        try self.moveToReg(@intCast(i), arg);
    }

    try self.emitInstr("bl", "_{s}", .{name});

    // Return value is in w0, save it to a temp register
    // (so it doesn't get clobbered by subsequent calls)
    const dest = self.allocTempReg(idx);
    try self.emitMov(dest, Reg.arg0); // dest <- w0
    try self.values.put(idx, Operand.inReg(dest));
}

// ============================================================================
// Register Allocation
// ============================================================================

/// Allocate a temp register for instruction result (simple: round-robin w8-w15)
fn allocTempReg(self: *Gen, idx: u32) u8 {
    _ = self;
    return Reg.temp_start + @as(u8, @intCast(idx % Reg.temp_count));
}

/// Ensure operand is in a register; load immediate into scratch if needed
fn materialize(self: *Gen, op: Operand, scratch: u8) !u8 {
    switch (op) {
        .imm => |v| {
            try self.emitInstr("mov", "w{d}, #{d}", .{ scratch, v });
            return scratch;
        },
        .reg => |r| return r,
    }
}

/// Move operand to specific register (skip if already there)
fn moveToReg(self: *Gen, dest: u8, op: Operand) !void {
    switch (op) {
        .imm => |v| try self.emitInstr("mov", "w{d}, #{d}", .{ dest, v }),
        .reg => |r| if (r != dest) try self.emitInstr("mov", "w{d}, w{d}", .{ dest, r }),
    }
}

// ============================================================================
// Helpers
// ============================================================================

fn findDecl(self: *Gen, function: zir_mod.Function, name: []const u8, before_idx: u32) ?u32 {
    _ = self;
    var i = before_idx;
    while (i > 0) {
        i -= 1;
        const inst = function.instructionAt(i);
        if (inst.* == .decl and mem.eql(u8, inst.decl.name, name)) {
            return inst.decl.value;
        }
    }
    return null;
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

/// Emit: mov wDst, wSrc  (dst <- src)
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
        \\    add w10, w16, #2
        \\    mov w0, w10
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
        \\    mul w10, w0, w0
        \\    mov w0, w10
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
        \\    add w10, w0, w1
        \\    mov w0, w10
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
        \\    sub w10, w0, w1
        \\    mov w0, w10
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
        \\    sdiv w10, w0, w1
        \\    mov w0, w10
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
        \\    add w10, w0, w1
        \\    mov w0, w10
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
        \\    mov w10, w0
        \\    mov w0, w10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}
