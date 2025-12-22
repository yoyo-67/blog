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

fn generate(self: *Zir, allocator: mem.Allocator, node: Node) !void {
    for (node.root.decls) |decl| {
        switch (decl) {
            .int_literal => |int_decl| {
                try self.emit(allocator, .{ .constant = .{ .value = int_decl.value } });
            },

            else => unreachable,
        }
    }
}

fn emit(self: *Zir, allocator: mem.Allocator, instruction: Instruction) !void {
    try self.instructions.append(allocator, instruction);
}

fn toString(self: *Zir, allocator: mem.Allocator) ![]const u8 {
    _ = self; // autofix
    _ = self; // autofix
    _ = allocator; // autofix
    return "";
}

const InstructionRef = u32;

const Instruction = union(enum) {
    constant: struct { value: i32 },
};

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
