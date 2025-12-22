const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const token_mod = @import("token.zig");
const ast_mod = @import("ast.zig");
const node_mod = @import("node.zig");
const Node = node_mod.Node;

const Zir = @This();

fn init() Zir {
    return .{};
}

fn generate(self: *Zir, allocator: mem.Allocator, node: Node) ![]const Instruction {
    _ = self; // autofix
    var items: std.ArrayListUnmanaged(Instruction) = .empty;
    for (node.root.decls) |decl| {
        switch (decl) {
            .int_literal => |int_decl| {
                try items.append(allocator, int_decl.value);
            },
        }
    }
    return items.toOwnedSlice(allocator);
}

const InstructionRef = u32;

const Instruction = union(enum) {};

test "constant: 42" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try ast_mod.parseExpr(&arena, "1 + 2");

    var zir = Zir.init();
    defer arena.deinit();

    _ = try zir.generate(allocator, tree);

    const result = try zir.toString(allocator);
    defer allocator.free(result);

    try testing.expectEqualStrings(
        \\%0 = constant(1)
        \\%1 = constant(2)
        \\%2 = add(%0, %1)
        \\
    , result);
}
