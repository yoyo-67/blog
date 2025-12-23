const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const token_mod = @import("token.zig");
const ast_mod = @import("ast.zig");
const node_mod = @import("node.zig");
const Node = node_mod.Node;

const Zir = @This();

instructions: std.ArrayListUnmanaged(Instruction),

fn init() Zir {
    return .{
        .instructions = .empty,
    };
}

fn generate(self: *Zir, allocator: mem.Allocator, node: Node) !InstructionRef {
    switch (node) {
        .int_literal => |lit| return try self.emit(allocator, .{ .constant = lit.value }),
        .binary_op => |bin| {
            const lhs = try self.generate(allocator, bin.lhs.*);
            const rhs = try self.generate(allocator, bin.rhs.*);
            return switch (bin.op) {
                .plus => try self.emit(allocator, .{ .add = .{ .lhs = lhs, .rhs = rhs } }),
                .mul => try self.emit(allocator, .{ .mul = .{ .lhs = lhs, .rhs = rhs } }),
                else => unreachable,
            };
        },
        .root => |root| {
            var last: InstructionRef = 0;
            for (root.decls) |decl| {
                last = try self.generate(allocator, decl);
            }
            return last;
        },
        .identifier => |val| {
            const instruction_ref = try self.generate(allocator, val.value.*);
            return try self.emit(allocator, .{ .decl = .{
                .name = val.name,
                .value = instruction_ref,
            } });
        },
        else => unreachable,
    }
}

fn emit(self: *Zir, allocator: mem.Allocator, instruction: Instruction) !InstructionRef {
    const idx: u32 = @intCast(self.instructions.items.len);
    try self.instructions.append(allocator, instruction);
    return idx;
}

fn toString(self: *Zir, allocator: mem.Allocator) ![]const u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    const writer = buffer.writer(allocator);
    for (self.instructions.items, 0..) |instruction, idx| {
        try instruction.toString(idx, writer);
        try writer.writeAll("\n");
    }
    return buffer.toOwnedSlice(allocator);
}

const InstructionRef = u32;

const Instruction = union(enum) {
    constant: i32,
    add: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
    },
    mul: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
    },
    decl: struct {
        name: []const u8,
        value: InstructionRef,
    },
    decl_ref: []const u8,

    pub fn toString(self: Instruction, idx: usize, writer: anytype) !void {
        try writer.print("%{d} = ", .{idx});
        switch (self) {
            .constant => |val| try writer.print("constant({d})", .{val}),
            .add => |val| try writer.print("add(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .mul => |val| try writer.print("mul(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .decl => |val| try writer.print("decl(\"{s}\", %{d})", .{ val.name, val.value }),
            .decl_ref => |val| try writer.print("decl_ref(\"{s}\")", .{val}),
        }
    }
};

fn deinit(self: *Zir, allocator: mem.Allocator) void {
    self.instructions.deinit(allocator);
}

test "constant: 42" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try ast_mod.parseExpr(&arena, "1 + 2 * 3 + 3");

    var zir = Zir.init();
    defer zir.deinit(allocator);

    _ = try zir.generate(allocator, tree);

    const result = try zir.toString(allocator);
    defer allocator.free(result);

    // 1 + 2 * 3  parses as  1 + (2 * 3) + 3
    try testing.expectEqualStrings(
        \\%0 = constant(1)
        \\%1 = constant(2)
        \\%2 = constant(3)
        \\%3 = mul(%1, %2)
        \\%4 = add(%0, %3)
        \\%5 = constant(3)
        \\%6 = add(%4, %5)
        \\
    , result);
}

test "variables" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try ast_mod.parseExpr(&arena, "const x = 42;");

    var zir = Zir.init();
    defer zir.deinit(allocator);

    _ = try zir.generate(allocator, tree);

    const result = try zir.toString(allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings(
        \\%0 = constant(42)
        \\%1 = decl("x", %0)
        \\
    , result);
}

test "var with math" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try ast_mod.parseExpr(&arena, "const x = 42 + 3;");

    var zir = Zir.init();
    defer zir.deinit(allocator);

    _ = try zir.generate(allocator, tree);

    const result = try zir.toString(allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings(
        \\%0 = constant(42)
        \\%1 = constant(3)
        \\%2 = add(%0, %1)
        \\%3 = decl("x", %2)
        \\
    , result);
}
