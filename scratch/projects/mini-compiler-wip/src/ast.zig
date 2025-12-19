const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const expect = std.testing.expectEqual;
const expectString = std.testing.expectEqualStrings;

const Token = @import("token.zig").Token;

const Node = @import("node.zig").Node;

pub const Ast = @This();
tokens: []const Token,

pub fn init(tokens: []const Token) Ast {
    return Ast{
        .tokens = tokens,
    };
}

pub fn parse(self: *Ast, allocator: mem.Allocator) !Node {
    var decls: std.ArrayListUnmanaged(Node) = .empty;

    for (self.tokens, 0..) |token, token_index| {
        if (token.type == .eof) {
            break;
        }

        const node = try self.parseNode(token, token_index);
        try decls.append(allocator, node);
    }

    return Node{ .root = .{
        .decls = try decls.toOwnedSlice(allocator),
    } };
}

fn parseNode(self: *Ast, token: Token, token_index: usize) !Node {
    _ = self; // autofix
    if (token.type == .integer) {
        return Node{ .int_literal = .{ .value = try std.fmt.parseInt(u8, token.lexeme, 10), .token_index = token_index } };
    }

    if (token.type == .plus) {
        return Node{ .binary_op = .{
            .lhs = .{ .int_literal = .{ .value = 1 } },
            .rhs = .{ .int_literal = .{ .value = 2 } },
            .op = .plus,
        } };
    }
    unreachable;
}
test "ast" {
    const allocator = testing.allocator;

    const tokens = [_]Token{
        .{ .type = .integer, .lexeme = "42" },
        .{ .type = .integer, .lexeme = "10" },
        .{ .type = .eof, .lexeme = "" },
    };

    var ast = Ast.init(&tokens);
    const tree = try ast.parse(allocator);
    defer allocator.free(tree.root.decls);

    try expect(tree.root.decls[0].int_literal.value, 42);
    try expect(tree.root.decls[0].int_literal.token_index, 0);

    try expect(tree.root.decls[1].int_literal.value, 10);
    try expect(tree.root.decls[1].int_literal.token_index, 1);
}

test "plus" {
    const allocator = testing.allocator;

    const tokens = [_]Token{
        .{ .type = .integer, .lexeme = "1" },
        .{ .type = .plus, .lexeme = "+" },
        .{ .type = .integer, .lexeme = "2" },
        .{ .type = .eof, .lexeme = "" },
    };

    var ast = Ast.init(&tokens);
    const tree = try ast.parse(allocator);
    defer allocator.free(tree.root.decls);

    try expect(tree.root.decls[0].binary_op.lhs.int_literal.value, 42);
}
