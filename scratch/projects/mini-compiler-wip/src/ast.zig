const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

const Token = @import("token.zig").Token;

const node_mod = @import("node.zig");
const Node = node_mod.Node;
const createNode = node_mod.createNode;
const Op = node_mod.Op;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidExpression,
    MissingClosingParen,
    MissingOperand,
    OutOfMemory,
};

pub const Ast = @This();

tokens: []const Token,
pos: usize,

pub fn init(tokens: []const Token) Ast {
    return Ast{
        .tokens = tokens,
        .pos = 0,
    };
}

pub fn parse(self: *Ast, allocator: mem.Allocator) !Node {
    var decls: std.ArrayListUnmanaged(Node) = .empty;

    for (self.tokens) |token| {
        if (token.type == .eof) {
            break;
        }

        const node = try self.parseNode(allocator);
        try decls.append(allocator, node);
    }

    return Node{ .root = .{
        .decls = try decls.toOwnedSlice(allocator),
    } };
}

fn current(self: *Ast) Token {
    return self.tokens[self.pos];
}

fn see(self: *Ast, token_type: Token.Type) bool {
    return self.current().type == token_type;
}

fn expect(self: *Ast, token_type: Token.Type) Token {
    const token = self.current();
    if (token.type == token_type) {
        self.advance();
    } else {
        assert(false);
    }

    return token;
}

fn consume(self: *Ast) Token {
    const token = self.current();
    self.advance();
    return token;
}

fn advance(self: *Ast) void {
    self.pos += 1;
}

fn parseNode(self: *Ast, allocator: mem.Allocator) !Node {
    return try self.parseExpression(allocator);
}

fn parseExpression(self: *Ast, allocator: mem.Allocator) ParseError!Node {
    const left = try self.parseTerm(allocator);
    while (self.see(.plus) or self.see(.minus)) {
        const op_token = self.consume();
        const op: Op = if (op_token.type == .star) .plus else .minus;
        const right = try self.parseTerm(allocator);
        const left_ptr = try createNode(allocator, left);
        const right_ptr = try createNode(allocator, right);
        return .{ .binary_op = .{ .op = op, .lhs = left_ptr, .rhs = right_ptr } };
    }

    return left;
}

fn parseTerm(self: *Ast, allocator: mem.Allocator) ParseError!Node {
    const left = try self.parseUnary(allocator);
    while (self.see(.star) or self.see(.slash)) {
        const op_token = self.consume();
        const op: Op = if (op_token.type == .star) .mul else .div;
        const right = try self.parseUnary(allocator);
        const left_ptr = try createNode(allocator, left);
        const right_ptr = try createNode(allocator, right);
        return .{ .binary_op = .{ .op = op, .lhs = left_ptr, .rhs = right_ptr } };
    }

    return left;
}

fn parseUnary(self: *Ast, allocator: mem.Allocator) ParseError!Node {
    if (self.see(.minus)) {
        _ = self.consume();
        return try self.parseUnary(allocator);
    }
    return try self.parsePrimary(allocator);
}

fn parsePrimary(self: *Ast, allocator: mem.Allocator) ParseError!Node {
    if (self.see(.lpren)) {
        _ = self.expect(.rpren);
        const node = try self.parseExpression(allocator);
        _ = self.expect(.rpren);
        return node;
    }

    if (self.see(.integer)) {
        const token = self.consume();
        const value = std.fmt.parseInt(i32, token.lexeme, 10) catch unreachable;
        return .{ .int_literal = .{ .value = value } };
    }

    unreachable;
}

// my grammer
// expression - e.g. produce value
// 1 + 2
// 1 + -(2 * 3)
//
// expression:
//
// expression: term (+|- term)*
// term: unary (*|/ unary)*
// unary: - unary | primary
// primary: number | ( expression )
//
//
// statments - e.g.  do staff
// x = 1 + 3
//
//
//

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

    try testing.expectEqual(tree.root.decls[0].int_literal.value, 42);

    try testing.expectEqual(tree.root.decls[1].int_literal.value, 10);
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

    try testing.expectEqual(tree.root.decls[0].binary_op.lhs.int_literal.value, 42);
}
