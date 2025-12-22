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
        .int_literal => |int_decl| return try self.emit(allocator, .{ .constant = int_decl.value }),
        .root => |root_decl| {
        }

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

    pub fn toString(self: Instruction, idx: usize, writer: anytype) !void {
        try writer.print("%{d}) = ", .{idx});
        switch (self) {
            .constant => |val| try writer.print("constant({d})", .{val}),
        }
    }
};

test "constant: 42" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try ast_mod.parseExpr(&arena, "42");

    var zir = Zir.init();
    defer arena.deinit();

    _ = try zir.generate(allocator, tree);

    const result = try zir.toString(allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings(
        \\%0 = constant(42)
        \\
    , result);
}

