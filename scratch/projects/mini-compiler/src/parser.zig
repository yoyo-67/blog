//! Parser for Zig subset compiler
//!
//! Parses tokens into an Abstract Syntax Tree (AST).
//! Supports: functions, const/var declarations, if/while, expressions.

const std = @import("std");
const Allocator = std.mem.Allocator;

const lexer_mod = @import("lexer.zig");
const ast_mod = @import("ast.zig");

pub const Lexer = lexer_mod.Lexer;
pub const Token = lexer_mod.Token;
pub const TokenType = lexer_mod.TokenType;
pub const Node = ast_mod.Node;
pub const TypeExpr = ast_mod.TypeExpr;
pub const BinaryOp = ast_mod.BinaryOp;
pub const UnaryOp = ast_mod.UnaryOp;
pub const AssignOp = ast_mod.AssignOp;
pub const Param = ast_mod.Param;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidNumber,
    ExpectedIdentifier,
    ExpectedType,
    ExpectedExpression,
    OutOfMemory,
};

pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: Allocator,

    pub fn init(source: []const u8, allocator: Allocator) Parser {
        var lexer = Lexer.init(source);
        const tokens = lexer.tokenize(allocator) catch &[_]Token{};
        return .{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
        };
    }

    // ==================== Token helpers ====================

    fn current(self: *Parser) Token {
        if (self.pos >= self.tokens.len) {
            return .{ .type = .eof, .lexeme = "", .line = 0, .column = 0 };
        }
        return self.tokens[self.pos];
    }

    fn peek(self: *Parser, offset: usize) TokenType {
        const idx = self.pos + offset;
        if (idx >= self.tokens.len) return .eof;
        return self.tokens[idx].type;
    }

    fn advance(self: *Parser) Token {
        const tok = self.current();
        if (self.pos < self.tokens.len) {
            self.pos += 1;
        }
        return tok;
    }

    fn check(self: *Parser, t: TokenType) bool {
        return self.current().type == t;
    }

    fn match(self: *Parser, t: TokenType) bool {
        if (self.check(t)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn expect(self: *Parser, t: TokenType) ParseError!Token {
        if (self.check(t)) {
            return self.advance();
        }
        return ParseError.UnexpectedToken;
    }

    fn createNode(self: *Parser, node: Node) ParseError!*Node {
        return Node.create(self.allocator, node) catch return ParseError.OutOfMemory;
    }

    // ==================== Main parse entry ====================

    /// Parse entire source into a Root AST node
    pub fn parse(self: *Parser) ParseError!*Node {
        var decls: std.ArrayListUnmanaged(*Node) = .empty;
        errdefer decls.deinit(self.allocator);

        while (!self.check(.eof)) {
            const decl = try self.parseDeclaration();
            decls.append(self.allocator, decl) catch return ParseError.OutOfMemory;
        }

        return self.createNode(.{
            .root = .{
                .decls = decls.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            },
        });
    }

    // ==================== Declarations ====================

    fn parseDeclaration(self: *Parser) ParseError!*Node {
        // Check for pub modifier
        const is_pub = self.match(.keyword_pub);

        if (self.check(.keyword_fn)) {
            return self.parseFnDecl(is_pub);
        }
        if (self.check(.keyword_const)) {
            return self.parseConstDecl();
        }
        if (self.check(.keyword_var)) {
            return self.parseVarDecl();
        }

        return ParseError.UnexpectedToken;
    }

    fn parseFnDecl(self: *Parser, is_pub: bool) ParseError!*Node {
        _ = try self.expect(.keyword_fn);

        const name_tok = try self.expect(.identifier);
        const name = name_tok.lexeme;

        _ = try self.expect(.lparen);

        // Parse parameters
        var params: std.ArrayListUnmanaged(Param) = .empty;
        errdefer params.deinit(self.allocator);

        while (!self.check(.rparen) and !self.check(.eof)) {
            const param_name = try self.expect(.identifier);
            _ = try self.expect(.colon);
            const param_type = try self.parseTypeExpr();

            params.append(self.allocator, .{
                .name = param_name.lexeme,
                .type_expr = param_type,
            }) catch return ParseError.OutOfMemory;

            if (!self.match(.comma)) break;
        }

        _ = try self.expect(.rparen);

        // Parse return type
        const return_type = try self.parseTypeExpr();

        // Parse body
        const body = try self.parseBlock();

        return self.createNode(.{
            .fn_decl = .{
                .is_pub = is_pub,
                .name = name,
                .params = params.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
                .return_type = return_type,
                .body = body,
            },
        });
    }

    fn parseConstDecl(self: *Parser) ParseError!*Node {
        _ = try self.expect(.keyword_const);

        const name_tok = try self.expect(.identifier);
        const name = name_tok.lexeme;

        // Optional type annotation
        var type_expr: ?TypeExpr = null;
        if (self.match(.colon)) {
            type_expr = try self.parseTypeExpr();
        }

        _ = try self.expect(.equal);
        const value = try self.parseExpression();
        _ = try self.expect(.semicolon);

        return self.createNode(.{
            .const_decl = .{
                .name = name,
                .type_expr = type_expr,
                .value = value,
            },
        });
    }

    fn parseVarDecl(self: *Parser) ParseError!*Node {
        _ = try self.expect(.keyword_var);

        const name_tok = try self.expect(.identifier);
        const name = name_tok.lexeme;

        // Optional type annotation
        var type_expr: ?TypeExpr = null;
        if (self.match(.colon)) {
            type_expr = try self.parseTypeExpr();
        }

        // Optional initializer
        var value: ?*Node = null;
        if (self.match(.equal)) {
            value = try self.parseExpression();
        }

        _ = try self.expect(.semicolon);

        return self.createNode(.{
            .var_decl = .{
                .name = name,
                .type_expr = type_expr,
                .value = value,
            },
        });
    }

    // ==================== Type expressions ====================

    fn parseTypeExpr(self: *Parser) ParseError!TypeExpr {
        const tok = self.current();

        // Primitive types
        const prim: ?TypeExpr.PrimitiveType = switch (tok.type) {
            .type_i8 => .i8,
            .type_i16 => .i16,
            .type_i32 => .i32,
            .type_i64 => .i64,
            .type_u8 => .u8,
            .type_u16 => .u16,
            .type_u32 => .u32,
            .type_u64 => .u64,
            .type_f32 => .f32,
            .type_f64 => .f64,
            .type_bool => .bool,
            .type_void => .void,
            else => null,
        };

        if (prim) |p| {
            _ = self.advance();
            return .{ .primitive = p };
        }

        // Named type (identifier)
        if (tok.type == .identifier) {
            _ = self.advance();
            return .{ .named = tok.lexeme };
        }

        return ParseError.ExpectedType;
    }

    // ==================== Statements ====================

    fn parseBlock(self: *Parser) ParseError!*Node {
        _ = try self.expect(.lbrace);

        var statements: std.ArrayListUnmanaged(*Node) = .empty;
        errdefer statements.deinit(self.allocator);

        while (!self.check(.rbrace) and !self.check(.eof)) {
            const stmt = try self.parseStatement();
            statements.append(self.allocator, stmt) catch return ParseError.OutOfMemory;
        }

        _ = try self.expect(.rbrace);

        return self.createNode(.{
            .block = .{
                .statements = statements.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            },
        });
    }

    fn parseStatement(self: *Parser) ParseError!*Node {
        // const declaration
        if (self.check(.keyword_const)) {
            return self.parseConstDecl();
        }

        // var declaration
        if (self.check(.keyword_var)) {
            return self.parseVarDecl();
        }

        // return statement
        if (self.check(.keyword_return)) {
            return self.parseReturnStmt();
        }

        // if statement
        if (self.check(.keyword_if)) {
            return self.parseIfStmt();
        }

        // while statement
        if (self.check(.keyword_while)) {
            return self.parseWhileStmt();
        }

        // break
        if (self.match(.keyword_break)) {
            _ = try self.expect(.semicolon);
            return self.createNode(.break_stmt);
        }

        // continue
        if (self.match(.keyword_continue)) {
            _ = try self.expect(.semicolon);
            return self.createNode(.continue_stmt);
        }

        // Expression statement or assignment
        return self.parseExpressionOrAssignStmt();
    }

    fn parseReturnStmt(self: *Parser) ParseError!*Node {
        _ = try self.expect(.keyword_return);

        var value: ?*Node = null;
        if (!self.check(.semicolon)) {
            value = try self.parseExpression();
        }

        _ = try self.expect(.semicolon);

        return self.createNode(.{
            .return_stmt = .{ .value = value },
        });
    }

    fn parseIfStmt(self: *Parser) ParseError!*Node {
        _ = try self.expect(.keyword_if);
        _ = try self.expect(.lparen);
        const condition = try self.parseExpression();
        _ = try self.expect(.rparen);

        const then_block = try self.parseBlock();

        var else_block: ?*Node = null;
        if (self.match(.keyword_else)) {
            if (self.check(.keyword_if)) {
                // else if
                else_block = try self.parseIfStmt();
            } else {
                else_block = try self.parseBlock();
            }
        }

        return self.createNode(.{
            .if_stmt = .{
                .condition = condition,
                .then_block = then_block,
                .else_block = else_block,
            },
        });
    }

    fn parseWhileStmt(self: *Parser) ParseError!*Node {
        _ = try self.expect(.keyword_while);
        _ = try self.expect(.lparen);
        const condition = try self.parseExpression();
        _ = try self.expect(.rparen);

        const body = try self.parseBlock();

        return self.createNode(.{
            .while_stmt = .{
                .condition = condition,
                .body = body,
            },
        });
    }

    fn parseExpressionOrAssignStmt(self: *Parser) ParseError!*Node {
        const expr = try self.parseExpression();

        // Check for assignment operators
        const assign_op: ?AssignOp = switch (self.current().type) {
            .equal => .assign,
            .plus_equal => .add_assign,
            .minus_equal => .sub_assign,
            .star_equal => .mul_assign,
            .slash_equal => .div_assign,
            else => null,
        };

        if (assign_op) |op| {
            _ = self.advance();
            const value = try self.parseExpression();
            _ = try self.expect(.semicolon);

            return self.createNode(.{
                .assign_stmt = .{
                    .target = expr,
                    .op = op,
                    .value = value,
                },
            });
        }

        _ = try self.expect(.semicolon);
        return self.createNode(.{
            .expr_stmt = .{ .expr = expr },
        });
    }

    // ==================== Expressions ====================

    fn parseExpression(self: *Parser) ParseError!*Node {
        return self.parseOr();
    }

    fn parseOr(self: *Parser) ParseError!*Node {
        var left = try self.parseAnd();

        while (self.match(.keyword_or)) {
            const right = try self.parseAnd();
            left = try self.createNode(.{
                .binary = .{ .op = .@"or", .left = left, .right = right },
            });
        }

        return left;
    }

    fn parseAnd(self: *Parser) ParseError!*Node {
        var left = try self.parseEquality();

        while (self.match(.keyword_and)) {
            const right = try self.parseEquality();
            left = try self.createNode(.{
                .binary = .{ .op = .@"and", .left = left, .right = right },
            });
        }

        return left;
    }

    fn parseEquality(self: *Parser) ParseError!*Node {
        var left = try self.parseComparison();

        while (true) {
            const op: ?BinaryOp = switch (self.current().type) {
                .equal_equal => .eq,
                .bang_equal => .neq,
                else => null,
            };

            if (op) |o| {
                _ = self.advance();
                const right = try self.parseComparison();
                left = try self.createNode(.{
                    .binary = .{ .op = o, .left = left, .right = right },
                });
            } else break;
        }

        return left;
    }

    fn parseComparison(self: *Parser) ParseError!*Node {
        var left = try self.parseAdditive();

        while (true) {
            const op: ?BinaryOp = switch (self.current().type) {
                .less => .lt,
                .less_equal => .lte,
                .greater => .gt,
                .greater_equal => .gte,
                else => null,
            };

            if (op) |o| {
                _ = self.advance();
                const right = try self.parseAdditive();
                left = try self.createNode(.{
                    .binary = .{ .op = o, .left = left, .right = right },
                });
            } else break;
        }

        return left;
    }

    fn parseAdditive(self: *Parser) ParseError!*Node {
        var left = try self.parseMultiplicative();

        while (true) {
            const op: ?BinaryOp = switch (self.current().type) {
                .plus => .add,
                .minus => .sub,
                else => null,
            };

            if (op) |o| {
                _ = self.advance();
                const right = try self.parseMultiplicative();
                left = try self.createNode(.{
                    .binary = .{ .op = o, .left = left, .right = right },
                });
            } else break;
        }

        return left;
    }

    fn parseMultiplicative(self: *Parser) ParseError!*Node {
        var left = try self.parseUnary();

        while (true) {
            const op: ?BinaryOp = switch (self.current().type) {
                .star => .mul,
                .slash => .div,
                .percent => .mod,
                else => null,
            };

            if (op) |o| {
                _ = self.advance();
                const right = try self.parseUnary();
                left = try self.createNode(.{
                    .binary = .{ .op = o, .left = left, .right = right },
                });
            } else break;
        }

        return left;
    }

    fn parseUnary(self: *Parser) ParseError!*Node {
        if (self.match(.minus)) {
            const operand = try self.parseUnary();
            return self.createNode(.{
                .unary = .{ .op = .neg, .operand = operand },
            });
        }

        if (self.match(.bang)) {
            const operand = try self.parseUnary();
            return self.createNode(.{
                .unary = .{ .op = .not, .operand = operand },
            });
        }

        return self.parseCall();
    }

    fn parseCall(self: *Parser) ParseError!*Node {
        var expr = try self.parsePrimary();

        while (self.match(.lparen)) {
            // Parse arguments
            var args: std.ArrayListUnmanaged(*Node) = .empty;
            errdefer args.deinit(self.allocator);

            while (!self.check(.rparen) and !self.check(.eof)) {
                const arg = try self.parseExpression();
                args.append(self.allocator, arg) catch return ParseError.OutOfMemory;

                if (!self.match(.comma)) break;
            }

            _ = try self.expect(.rparen);

            expr = try self.createNode(.{
                .call = .{
                    .callee = expr,
                    .args = args.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
                },
            });
        }

        return expr;
    }

    fn parsePrimary(self: *Parser) ParseError!*Node {
        const tok = self.current();

        switch (tok.type) {
            .int_literal => {
                _ = self.advance();
                const value = std.fmt.parseInt(i64, tok.lexeme, 10) catch
                    return ParseError.InvalidNumber;
                return self.createNode(.{ .int_literal = value });
            },
            .float_literal => {
                _ = self.advance();
                const value = std.fmt.parseFloat(f64, tok.lexeme) catch
                    return ParseError.InvalidNumber;
                return self.createNode(.{ .float_literal = value });
            },
            .keyword_true => {
                _ = self.advance();
                return self.createNode(.{ .bool_literal = true });
            },
            .keyword_false => {
                _ = self.advance();
                return self.createNode(.{ .bool_literal = false });
            },
            .string_literal => {
                _ = self.advance();
                // Remove quotes
                const s = tok.lexeme;
                const content = if (s.len >= 2) s[1 .. s.len - 1] else s;
                return self.createNode(.{ .string_literal = content });
            },
            .identifier => {
                _ = self.advance();
                return self.createNode(.{ .identifier = tok.lexeme });
            },
            .lparen => {
                _ = self.advance();
                const expr = try self.parseExpression();
                _ = try self.expect(.rparen);
                return self.createNode(.{ .grouped = .{ .expr = expr } });
            },
            else => return ParseError.ExpectedExpression,
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "parse const declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init("const x: i32 = 5;", allocator);
    const ast = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), ast.root.decls.len);
    try std.testing.expectEqualStrings("x", ast.root.decls[0].const_decl.name);
}

test "parse function declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init("pub fn add(a: i32, b: i32) i32 { return a + b; }", allocator);
    const ast = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), ast.root.decls.len);
    const func = ast.root.decls[0].fn_decl;
    try std.testing.expect(func.is_pub);
    try std.testing.expectEqualStrings("add", func.name);
    try std.testing.expectEqual(@as(usize, 2), func.params.len);
}

test "parse if statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init("fn test() void { if (x > 5) { return; } }", allocator);
    const ast = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), ast.root.decls.len);
}

test "parse while statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init("fn test() void { while (x > 0) { x -= 1; } }", allocator);
    const ast = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), ast.root.decls.len);
}

test "parse expression with precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init("const x: i32 = 3 + 5 * 2;", allocator);
    const ast = try parser.parse();

    const value = ast.root.decls[0].const_decl.value;
    // Should be Add(3, Mul(5, 2)) due to precedence
    try std.testing.expectEqual(BinaryOp.add, value.binary.op);
    try std.testing.expectEqual(BinaryOp.mul, value.binary.right.binary.op);
}
