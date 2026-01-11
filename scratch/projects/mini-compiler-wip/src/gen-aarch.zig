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

output: std.ArrayListUnmanaged(u8),
alloc: Allocator,
/// Maps instruction index -> register where result lives
locs: [256]u8,

pub fn init(alloc: Allocator) Gen {
    return .{
        .output = .empty,
        .alloc = alloc,
        .locs = undefined,
    };
}

pub fn writer(self: *Gen) std.ArrayListUnmanaged(u8).Writer {
    return self.output.writer(self.alloc);
}

pub fn generate(self: *Gen, program: zir_mod.Program) !void {
    for (program.functions()) |func| {
        const sema_result = try sema_mod.analyzeFunction(self.alloc, func);
        const lowered = try lower_mod.lower(self.alloc, sema_result.function);
        try self.emitFunction(lowered);
        try self.writer().writeAll("\n");
    }
}

// ============================================================================
// Function Emission
// ============================================================================

fn emitFunction(self: *Gen, function: LoweredFunction) !void {
    try self.writer().print(".global _{s}\n", .{function.name});
    try self.writer().print("_{s}:\n", .{function.name});
    try self.writer().writeAll("    stp x29, x30, [sp, #-16]!\n");
    try self.writer().writeAll("    mov x29, sp\n");

    for (function.instructions, 0..) |inst, idx| {
        try self.emitInstruction(inst, @intCast(idx));
    }
}

fn emitInstruction(self: *Gen, inst: LoweredInst, idx: u32) !void {
    switch (inst) {
        .add => |op| try self.emitBinaryOp(idx, "add", op.lhs, op.rhs),
        .sub => |op| try self.emitBinaryOp(idx, "sub", op.lhs, op.rhs),
        .mul => |op| try self.emitBinaryOp(idx, "mul", op.lhs, op.rhs),
        .div => |op| try self.emitBinaryOp(idx, "sdiv", op.lhs, op.rhs),
        .ret => |op| try self.emitReturn(op),
        .call => |c| try self.emitCall(idx, c.name, c.args),
    }
}

fn emitBinaryOp(self: *Gen, idx: u32, mnemonic: []const u8, lhs: Operand, rhs: Operand) !void {
    const dest: u8 = 8 + @as(u8, @intCast(idx % 8));
    self.locs[idx] = dest;

    const lhs_reg = try self.materialize(lhs, 16);
    const rhs_reg = try self.materialize(rhs, 17);
    try self.writer().print("    {s} w{d}, w{d}, w{d}\n", .{ mnemonic, dest, lhs_reg, rhs_reg });
}

fn emitReturn(self: *Gen, op: Operand) !void {
    try self.moveToReg(0, op);
    try self.writer().writeAll("    ldp x29, x30, [sp], #16\n");
    try self.writer().writeAll("    ret\n");
}

fn emitCall(self: *Gen, idx: u32, name: []const u8, args: []const Operand) !void {
    for (args, 0..) |arg, i| {
        try self.moveToReg(@intCast(i), arg);
    }
    try self.writer().print("    bl _{s}\n", .{name});

    const dest: u8 = 8 + @as(u8, @intCast(idx % 8));
    self.locs[idx] = dest;
    try self.writer().print("    mov w{d}, w0\n", .{dest});
}

fn materialize(self: *Gen, op: Operand, scratch: u8) !u8 {
    return switch (op) {
        .imm => |v| {
            try self.writer().print("    mov w{d}, #{d}\n", .{ scratch, v });
            return scratch;
        },
        .param => |i| i,
        .inst => |i| self.locs[i],
    };
}

fn moveToReg(self: *Gen, dest: u8, op: Operand) !void {
    switch (op) {
        .imm => |v| try self.writer().print("    mov w{d}, #{d}\n", .{ dest, v }),
        .param => |i| if (i != dest) try self.writer().print("    mov w{d}, w{d}\n", .{ dest, i }),
        .inst => |i| {
            const src = self.locs[i];
            if (src != dest) try self.writer().print("    mov w{d}, w{d}\n", .{ dest, src });
        },
    }
}

fn testGenerate(arena: *std.heap.ArenaAllocator, input: []const u8) ![]const u8 {
    const tree = try ast_mod.parseExpr(arena, input);
    const alloc = arena.allocator();
    const program = try zir_mod.generateProgram(alloc, &tree);

    var gen = Gen.init(alloc);
    try gen.generate(program);
    return try gen.output.toOwnedSlice(alloc);
}

test "simple return constant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena, "fn main() i32 { return 42; }");

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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena, "fn calc() i32 { return 1 + 2; }");

    try testing.expectEqualStrings(
        \\.global _calc
        \\_calc:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w16, #1
        \\    mov w17, #2
        \\    add w8, w16, w17
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function with parameter" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena, "fn square(x: i32) i32 { return x * x; }");

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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena, "fn add(a: i32, b: i32) i32 { return a + b; }");

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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena, "fn sub(a: i32, b: i32) i32 { return a - b; }");

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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena, "fn div(a: i32, b: i32) i32 { return a / b; }");

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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena,
        \\fn foo() i32 {
        \\  const x = 10;
        \\  return x;
        \\}
    );

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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena,
        \\fn foo() i32 { return 42; }
        \\fn main() i32 { return foo(); }
    );

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
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena,
        \\fn add(a: i32, b: i32) i32 { return a + b; }
        \\fn main() i32 { return add(3, 5); }
    );

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
