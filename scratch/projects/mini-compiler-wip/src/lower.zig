const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;

const sema_mod = @import("sema.zig");
const zir_mod = @import("zir.zig");
const ast_mod = @import("ast.zig");
const Type = @import("types.zig").Type;
const Value = @import("types.zig").Value;

// ============================================================================
// Lowered IR - ready for codegen, all operands resolved
// ============================================================================

/// Where a value comes from - backend maps this to concrete representation
pub const Operand = union(enum) {
    /// Immediate constant value
    imm: i64,
    /// Function parameter index
    param: u8,
    /// Result of instruction at this index
    inst: u32,
};

/// Lowered instruction - operands already resolved, ready to emit
pub const LoweredInst = union(enum) {
    add: BinaryOp,
    sub: BinaryOp,
    mul: BinaryOp,
    div: BinaryOp,
    ret: Operand,
    call: struct { name: []const u8, args: []const Operand },

    pub const BinaryOp = struct { lhs: Operand, rhs: Operand };
};

/// Lowered function - ready for codegen to iterate and emit
pub const LoweredFunction = struct {
    name: []const u8,
    params: []const zir_mod.Node.Param,
    return_type: ?Type,
    instructions: []const LoweredInst,
};

/// Transform TypedFunction -> LoweredFunction
/// Resolves all references, eliminates copy/literal/param_ref instructions
pub fn lower(allocator: Allocator, typed_func: sema_mod.TypedFunction) !LoweredFunction {
    // Map from sema instruction index to operand
    var operand_map: [256]Operand = undefined;
    var lowered = std.ArrayListUnmanaged(LoweredInst){};
    var emit_idx: u32 = 0;

    for (typed_func.instructions, 0..) |inst, idx| {
        switch (inst) {
            .literal => |v| {
                operand_map[idx] = .{ .imm = valueToI64(v) };
            },
            .param_ref => |i| {
                operand_map[idx] = .{ .param = @intCast(i) };
            },
            .decl => |d| {
                operand_map[idx] = operand_map[d.value];
            },
            .decl_ref => |d| {
                operand_map[idx] = operand_map[d.value];
            },
            .add => |op| {
                try lowered.append(allocator, .{ .add = .{
                    .lhs = operand_map[op.lhs],
                    .rhs = operand_map[op.rhs],
                } });
                operand_map[idx] = .{ .inst = emit_idx };
                emit_idx += 1;
            },
            .sub => |op| {
                try lowered.append(allocator, .{ .sub = .{
                    .lhs = operand_map[op.lhs],
                    .rhs = operand_map[op.rhs],
                } });
                operand_map[idx] = .{ .inst = emit_idx };
                emit_idx += 1;
            },
            .mul => |op| {
                try lowered.append(allocator, .{ .mul = .{
                    .lhs = operand_map[op.lhs],
                    .rhs = operand_map[op.rhs],
                } });
                operand_map[idx] = .{ .inst = emit_idx };
                emit_idx += 1;
            },
            .div => |op| {
                try lowered.append(allocator, .{ .div = .{
                    .lhs = operand_map[op.lhs],
                    .rhs = operand_map[op.rhs],
                } });
                operand_map[idx] = .{ .inst = emit_idx };
                emit_idx += 1;
            },
            .ret => |ref| {
                try lowered.append(allocator, .{ .ret = operand_map[ref] });
            },
            .call => |c| {
                // Resolve all args to operands
                var args = try allocator.alloc(Operand, c.args.len);
                for (c.args, 0..) |arg_ref, i| {
                    args[i] = operand_map[arg_ref];
                }
                try lowered.append(allocator, .{ .call = .{
                    .name = c.name,
                    .args = args,
                } });
                operand_map[idx] = .{ .inst = emit_idx };
                emit_idx += 1;
            },
        }
    }

    return .{
        .name = typed_func.name,
        .params = typed_func.params,
        .return_type = typed_func.return_type,
        .instructions = try lowered.toOwnedSlice(allocator),
    };
}

fn valueToI64(v: Value) i64 {
    return switch (v) {
        .int => |i| i,
        .float => |f| @intFromFloat(f),
        .boolean => |b| if (b) 1 else 0,
    };
}

// ============================================================================
// Tests
// ============================================================================

fn testLower(arena: *std.heap.ArenaAllocator, input: []const u8) !LoweredFunction {
    return testLowerNth(arena, input, 0);
}

fn testLowerNth(arena: *std.heap.ArenaAllocator, input: []const u8, func_idx: usize) !LoweredFunction {
    const allocator = arena.allocator();
    const tree = try ast_mod.parseExpr(arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const func = program.functions()[func_idx];
    const sema_result = try sema_mod.analyzeFunction(allocator, func);
    return try lower(allocator, sema_result.function);
}

test "lower: return constant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testLower(&arena, "fn main() i32 { return 42; }");

    // Should have just 1 instruction: ret(imm(42))
    try testing.expectEqual(@as(usize, 1), result.instructions.len);
    try testing.expectEqual(Operand{ .imm = 42 }, result.instructions[0].ret);
}

test "lower: return param" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testLower(&arena, "fn identity(x: i32) i32 { return x; }");

    // Should have just 1 instruction: ret(param(0))
    try testing.expectEqual(@as(usize, 1), result.instructions.len);
    try testing.expectEqual(Operand{ .param = 0 }, result.instructions[0].ret);
}

test "lower: add two constants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testLower(&arena, "fn calc() i32 { return 1 + 2; }");

    // Should have 2 instructions: add, ret
    try testing.expectEqual(@as(usize, 2), result.instructions.len);

    const add = result.instructions[0].add;
    try testing.expectEqual(Operand{ .imm = 1 }, add.lhs);
    try testing.expectEqual(Operand{ .imm = 2 }, add.rhs);

    try testing.expectEqual(Operand{ .inst = 0 }, result.instructions[1].ret);
}

test "lower: add two params" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testLower(&arena, "fn add(a: i32, b: i32) i32 { return a + b; }");

    // Should have 2 instructions: add, ret
    try testing.expectEqual(@as(usize, 2), result.instructions.len);

    const add = result.instructions[0].add;
    try testing.expectEqual(Operand{ .param = 0 }, add.lhs);
    try testing.expectEqual(Operand{ .param = 1 }, add.rhs);

    try testing.expectEqual(Operand{ .inst = 0 }, result.instructions[1].ret);
}

test "lower: variable is eliminated" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testLower(&arena,
        \\fn foo() i32 {
        \\  const x = 10;
        \\  return x;
        \\}
    );

    // const x = 10; return x; should become just: ret(imm(10))
    try testing.expectEqual(@as(usize, 1), result.instructions.len);
    try testing.expectEqual(Operand{ .imm = 10 }, result.instructions[0].ret);
}

test "lower: variable with computation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testLower(&arena,
        \\fn calc(n: i32) i32 {
        \\  const result = n + 1;
        \\  return result;
        \\}
    );

    // Should have 2 instructions: add(param(0), imm(1)), ret(inst(0))
    try testing.expectEqual(@as(usize, 2), result.instructions.len);

    const add = result.instructions[0].add;
    try testing.expectEqual(Operand{ .param = 0 }, add.lhs);
    try testing.expectEqual(Operand{ .imm = 1 }, add.rhs);

    try testing.expectEqual(Operand{ .inst = 0 }, result.instructions[1].ret);
}

test "lower: function call" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Get main (second function)
    const result = try testLowerNth(&arena,
        \\fn foo() i32 { return 42; }
        \\fn main() i32 { return foo(); }
    , 1);

    // main: call foo(), ret result
    try testing.expectEqual(@as(usize, 2), result.instructions.len);

    const call = result.instructions[0].call;
    try testing.expectEqualStrings("foo", call.name);
    try testing.expectEqual(@as(usize, 0), call.args.len);

    try testing.expectEqual(Operand{ .inst = 0 }, result.instructions[1].ret);
}

test "lower: function call with args" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Get main (second function)
    const result = try testLowerNth(&arena,
        \\fn add(a: i32, b: i32) i32 { return a + b; }
        \\fn main() i32 { return add(3, 5); }
    , 1);

    // main: call add(3, 5), ret result
    try testing.expectEqual(@as(usize, 2), result.instructions.len);

    const call = result.instructions[0].call;
    try testing.expectEqualStrings("add", call.name);
    try testing.expectEqual(@as(usize, 2), call.args.len);
    try testing.expectEqual(Operand{ .imm = 3 }, call.args[0]);
    try testing.expectEqual(Operand{ .imm = 5 }, call.args[1]);

    try testing.expectEqual(Operand{ .inst = 0 }, result.instructions[1].ret);
}

test "lower: chained arithmetic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testLower(&arena, "fn calc() i32 { return 1 + 2 + 3; }");

    // (1 + 2) + 3 -> add, add, ret
    try testing.expectEqual(@as(usize, 3), result.instructions.len);

    // First add: 1 + 2
    const add1 = result.instructions[0].add;
    try testing.expectEqual(Operand{ .imm = 1 }, add1.lhs);
    try testing.expectEqual(Operand{ .imm = 2 }, add1.rhs);

    // Second add: result + 3
    const add2 = result.instructions[1].add;
    try testing.expectEqual(Operand{ .inst = 0 }, add2.lhs);
    try testing.expectEqual(Operand{ .imm = 3 }, add2.rhs);

    try testing.expectEqual(Operand{ .inst = 1 }, result.instructions[2].ret);
}

test "lower: mixed operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testLower(&arena, "fn calc() i32 { return 2 * 3 + 4; }");

    // 2 * 3 + 4 -> mul, add, ret
    try testing.expectEqual(@as(usize, 3), result.instructions.len);

    const mul = result.instructions[0].mul;
    try testing.expectEqual(Operand{ .imm = 2 }, mul.lhs);
    try testing.expectEqual(Operand{ .imm = 3 }, mul.rhs);

    const add = result.instructions[1].add;
    try testing.expectEqual(Operand{ .inst = 0 }, add.lhs);
    try testing.expectEqual(Operand{ .imm = 4 }, add.rhs);

    try testing.expectEqual(Operand{ .inst = 1 }, result.instructions[2].ret);
}
