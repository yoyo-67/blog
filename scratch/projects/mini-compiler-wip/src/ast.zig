const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;
const Type = @import("types.zig").Type;

const node_mod = @import("node.zig");
const Node = node_mod.Node;
const createNode = node_mod.createNode;
const Op = node_mod.Op;

pub fn parseExpr(arena: *std.heap.ArenaAllocator, source: []const u8) !Node {
    const allocator = arena.allocator();
    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    var ast = Ast.init(tokens);
    return ast.parse(arena);
}

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

pub fn parse(self: *Ast, arena: *std.heap.ArenaAllocator) !Node {
    const allocator = arena.allocator();
    var decls: std.ArrayListUnmanaged(Node) = .empty;

    while (!self.see(.eof)) {
        const node = try self.parseNode(allocator);
        try decls.append(allocator, node);
    }

    return Node{ .root = .{
        .decls = try decls.toOwnedSlice(allocator),
    } };
}

fn current(self: *Ast) *const Token {
    return &self.tokens[self.pos];
}

fn see(self: *Ast, token_type: Token.Type) bool {
    return self.current().type == token_type;
}

fn expect(self: *Ast, token_type: Token.Type) *const Token {
    const token = self.current();
    if (token.*.type == token_type) {
        self.advance();
    } else {
        assert(false);
    }

    return token;
}

fn consume(self: *Ast) *const Token {
    const token = self.current();
    self.advance();
    return token;
}

fn advance(self: *Ast) void {
    self.pos += 1;
}

fn parseNode(self: *Ast, allocator: mem.Allocator) !Node {
    if (self.see(.kw_fn)) {
        return try self.parseFn(allocator);
    }
    if (self.see(.kw_const) or self.see(.kw_return)) {
        return try self.parseStatements(allocator);
    }
    return try self.parseExpression(allocator);
}

fn parseExpression(self: *Ast, allocator: mem.Allocator) ParseError!Node {
    var left = try self.parseTerm(allocator);
    while (self.see(.plus) or self.see(.minus)) {
        const token = self.consume();
        const op: Op = if (token.type == .plus) .plus else .minus;
        const right = try self.parseTerm(allocator);
        const left_ptr = try createNode(allocator, left);
        const right_ptr = try createNode(allocator, right);
        left = .{ .binary_op = .{ .op = op, .lhs = left_ptr, .rhs = right_ptr, .token = token } };
    }

    return left;
}

fn parseTerm(self: *Ast, allocator: mem.Allocator) ParseError!Node {
    var left = try self.parseUnary(allocator);
    while (self.see(.star) or self.see(.slash)) {
        const token = self.consume();
        const op: Op = if (token.type == .star) .mul else .div;
        const right = try self.parseUnary(allocator);
        const left_ptr = try createNode(allocator, left);
        const right_ptr = try createNode(allocator, right);
        left = .{ .binary_op = .{ .op = op, .lhs = left_ptr, .rhs = right_ptr, .token = token } };
    }

    return left;
}

fn parseUnary(self: *Ast, allocator: mem.Allocator) ParseError!Node {
    if (self.see(.minus)) {
        _ = self.consume();
        const operand = try self.parseUnary(allocator);
        // Double negation cancels out
        if (operand == .unary_op and operand.unary_op.op == .minus) {
            return operand.unary_op.operand.*;
        }
        const operand_ptr = try createNode(allocator, operand);
        return .{ .unary_op = .{ .op = .minus, .operand = operand_ptr } };
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

    if (self.see(.identifier)) {
        const token = self.consume();
        return .{ .identifier_ref = .{ .name = token.lexeme, .token = token } };
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
// primary: number | identifier | ( expression )
//
//
// statments - e.g.  do staff
// statements: var_decl | return_stmt
// var_decls: "const" IDENTIFIER '=' expression ';'
// return_stmt: 'return' expression ';'
//

fn parseStatements(self: *Ast, allocator: mem.Allocator) !Node {
    if (self.see(.kw_const)) {
        return self.parseVarDecl(allocator);
    }
    if (self.see(.kw_return)) {
        return self.parseReturnStmt(allocator);
    }
    unreachable;
}

fn parseVarDecl(self: *Ast, allocator: mem.Allocator) !Node {
    _ = self.expect(.kw_const);
    const token = self.consume();
    _ = self.expect(.equal);
    const value = try self.parseExpression(allocator);
    const value_ptr = try createNode(allocator, value);
    _ = self.expect(.semicolon);
    return .{ .identifier = .{ .name = token.lexeme, .value = value_ptr, .token = token } };
}

fn parseReturnStmt(self: *Ast, allocator: mem.Allocator) !Node {
    _ = self.expect(.kw_return);
    const expression = try self.parseExpression(allocator);
    _ = self.expect(.semicolon);

    const expression_ptr = try createNode(allocator, expression);
    return .{ .return_stmt = .{ .value = expression_ptr } };
}

// "fn add(a: i32, b: i32) { return a + b; }"
// fn: 'fn' IDENTIFIER '(' parameters? ')' return_type? '{' block '}'
// parameters: parameter (, parameter)*
// parameter: IDENTIFIER ':' IDENTIFIER
// return_type: Type
// block: statement*
//
fn parseFn(self: *Ast, allocator: mem.Allocator) !Node {
    var params: std.ArrayListUnmanaged(Node.Param) = .empty;
    const kw_fn = self.expect(.kw_fn);
    const name = self.expect(.identifier).lexeme;
    _ = self.expect(.lpren);
    if (!self.see(.rpren)) {
        try self.parseParams(allocator, &params);
    }
    _ = self.expect(.rpren);
    const return_type: ?Type = if (!self.see(.lbrace)) self.parseType() else null;
    _ = self.expect(.lbrace);
    const block = try self.parseBlock(allocator);
    _ = self.expect(.rbrace);

    return .{ .fn_decl = .{
        .name = name,
        .params = try params.toOwnedSlice(allocator),
        .block = block,
        .return_type = return_type,
        .token = kw_fn,
    } };
}

fn parseParams(self: *Ast, allocator: mem.Allocator, params: *std.ArrayListUnmanaged(Node.Param)) !void {
    // parameter: IDENTIFIER ':' TYPE
    while (true) {
        const param_name = self.expect(.identifier).lexeme;
        _ = self.expect(.colon);
        const param_type = self.parseType();
        try params.append(allocator, .{ .name = param_name, .type = param_type });
        if (!self.see(.comma)) break;
        _ = self.consume(); // consume comma
    }
}

fn parseType(self: *Ast) Type {
    if (self.see(.kw_i32)) {
        return Type.fromString(self.consume().lexeme);
    }
    if (self.see(.kw_bool)) {
        return Type.fromString(self.consume().lexeme);
    }
    if (self.see(.identifier)) {
        return Type.fromString(self.consume().lexeme);
    }
    unreachable;
}

fn parseBlock(self: *Ast, allocator: mem.Allocator) ParseError!Node.Block {
    var decls: std.ArrayListUnmanaged(Node) = .empty;
    while (!self.see(.rbrace) and !self.see(.eof)) {
        const node = try self.parseNode(allocator);
        try decls.append(allocator, node);
    }
    return .{ .decls = try decls.toOwnedSlice(allocator) };
}

test "simple addition: 1 + 2" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "1 + 2");
    try testing.expectEqualStrings("(1 + 2)", try tree.toString(arena.allocator()));
}

test "simple multiplication: 3 * 4" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "3 * 4");
    try testing.expectEqualStrings("(3 * 4)", try tree.toString(arena.allocator()));
}

test "precedence: 1 + 2 * 3" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "1 + 2 * 3");
    try testing.expectEqualStrings("(1 + (2 * 3))", try tree.toString(arena.allocator()));
}

test "precedence: 1 * 2 + 3" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "1 * 2 + 3");
    try testing.expectEqualStrings("((1 * 2) + 3)", try tree.toString(arena.allocator()));
}

test "left associativity: 1 - 2 - 3" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "1 - 2 - 3");
    try testing.expectEqualStrings("((1 - 2) - 3)", try tree.toString(arena.allocator()));
}

test "left associativity: 8 / 4 / 2" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "8 / 4 / 2");
    try testing.expectEqualStrings("((8 / 4) / 2)", try tree.toString(arena.allocator()));
}

test "complex: 1 + 2 * 3 - 4 / 2" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "1 + 2 * 3 - 4 / 2");
    try testing.expectEqualStrings("((1 + (2 * 3)) - (4 / 2))", try tree.toString(arena.allocator()));
}

test "single number" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "-42");
    try testing.expectEqualStrings("-42", try tree.toString(arena.allocator()));
}

test "statements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "const x = 4 + 4 * ----2;");
    try testing.expectEqualStrings("identifier(name=x, value=(4 + (4 * 2)))", try tree.toString(arena.allocator()));
}

test "return statment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "return 4 + 4;");
    try testing.expectEqualStrings("return(value=(4 + 4))", try tree.toString(arena.allocator()));
}

test "fn declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try parseExpr(&arena, "fn add(a: i32, b: i32) { return 1 + 2; }");
    try testing.expectEqualStrings("fn(name=add, params=[param(name=a, type=i32), param(name=b, type=i32)], block=return(value=(1 + 2)))", try tree.toString(arena.allocator()));
}

test "return identifier ref" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const str =
        \\ const x = 10;                                                                                                              
        \\ return x;                                                                                                                  
    ;
    const tree = try parseExpr(&arena, str);
    try testing.expectEqualStrings("identifier(name=x, value=10), return(value=x)", try tree.toString(arena.allocator()));
}
