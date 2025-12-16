//! Parser for the mini math compiler
//!
//! Converts tokens into an Abstract Syntax Tree (AST) using recursive descent.
//!
//! Grammar:
//!   program    → statement (";" statement)* EOF
//!   statement  → assignment | expression
//!   assignment → IDENTIFIER "=" expression
//!   expression → term (("+"|"-") term)*
//!   term       → factor (("*"|"/"|"%") factor)*
//!   factor     → unary | primary
//!   unary      → "-" factor | primary
//!   primary    → NUMBER | IDENTIFIER | "(" expression ")"

const std = @import("std");
const Allocator = std.mem.Allocator;

const lexer_mod = @import("lexer.zig");
const ast_mod = @import("ast.zig");

pub const Lexer = lexer_mod.Lexer;
pub const Token = lexer_mod.Token;
pub const TokenType = lexer_mod.TokenType;
pub const Node = ast_mod.Node;
pub const BinaryOp = ast_mod.BinaryOp;
pub const UnaryOp = ast_mod.UnaryOp;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidNumber,
    OutOfMemory,
};

pub const Parser = struct {
    lexer: Lexer,
    current: Token,
    allocator: Allocator,

    pub fn init(source: []const u8, allocator: Allocator) Parser {
        var lexer = Lexer.init(source);
        const first_token = lexer.nextToken();
        return .{
            .lexer = lexer,
            .current = first_token,
            .allocator = allocator,
        };
    }

    /// Advance to the next token
    fn advance(self: *Parser) void {
        self.current = self.lexer.nextToken();
    }

    /// Check if current token matches expected type
    fn check(self: *Parser, expected: TokenType) bool {
        return self.current.type == expected;
    }

    /// Consume token if it matches, otherwise error
    fn expect(self: *Parser, expected: TokenType) ParseError!void {
        if (self.current.type != expected) {
            return ParseError.UnexpectedToken;
        }
        self.advance();
    }

    /// Create a new AST node
    fn createNode(self: *Parser, node: Node) ParseError!*Node {
        return Node.create(self.allocator, node) catch return ParseError.OutOfMemory;
    }

    /// Parse the entire program
    /// program → statement (";" statement)* EOF
    pub fn parse(self: *Parser) ParseError!*Node {
        var statements: std.ArrayList(*Node) = .empty;

        // Parse first statement
        const first = try self.parseStatement();
        statements.append(self.allocator, first) catch return ParseError.OutOfMemory;

        // Parse remaining statements separated by semicolons
        while (self.current.type == .semicolon) {
            self.advance(); // consume ';'
            if (self.current.type == .eof) break;
            const stmt = try self.parseStatement();
            statements.append(self.allocator, stmt) catch return ParseError.OutOfMemory;
        }

        // If only one statement, return it directly
        if (statements.items.len == 1) {
            const result = statements.items[0];
            statements.deinit(self.allocator);
            return result;
        }

        return self.createNode(.{
            .statement_list = .{
                .statements = statements.toOwnedSlice(self.allocator) catch
                    return ParseError.OutOfMemory,
            },
        });
    }

    /// Parse a statement (assignment or expression)
    /// statement → assignment | expression
    fn parseStatement(self: *Parser) ParseError!*Node {
        // Check for assignment: IDENTIFIER "="
        if (self.current.type == .identifier) {
            const name = self.current.lexeme;

            // Peek ahead to check for '='
            var peek_lexer = self.lexer;
            const peek_token = peek_lexer.nextToken();

            if (peek_token.type == .equals) {
                self.advance(); // consume identifier
                self.advance(); // consume '='
                const value = try self.parseExpression();
                return self.createNode(.{
                    .assignment = .{ .name = name, .value = value },
                });
            }
        }

        return self.parseExpression();
    }

    /// Parse an expression (addition/subtraction level)
    /// expression → term (("+"|"-") term)*
    fn parseExpression(self: *Parser) ParseError!*Node {
        var left = try self.parseTerm();

        while (self.current.type == .plus or self.current.type == .minus) {
            const op: BinaryOp = if (self.current.type == .plus) .add else .sub;
            self.advance();
            const right = try self.parseTerm();
            left = try self.createNode(.{
                .binary = .{ .op = op, .left = left, .right = right },
            });
        }

        return left;
    }

    /// Parse a term (multiplication/division/modulo level)
    /// term → factor (("*"|"/"|"%") factor)*
    fn parseTerm(self: *Parser) ParseError!*Node {
        var left = try self.parseFactor();

        while (self.current.type == .star or
            self.current.type == .slash or
            self.current.type == .percent)
        {
            const op: BinaryOp = switch (self.current.type) {
                .star => .mul,
                .slash => .div,
                .percent => .mod,
                else => unreachable,
            };
            self.advance();
            const right = try self.parseFactor();
            left = try self.createNode(.{
                .binary = .{ .op = op, .left = left, .right = right },
            });
        }

        return left;
    }

    /// Parse a factor (unary operators)
    /// factor → "-" factor | primary
    fn parseFactor(self: *Parser) ParseError!*Node {
        // Unary minus
        if (self.current.type == .minus) {
            self.advance();
            const operand = try self.parseFactor();
            return self.createNode(.{
                .unary = .{ .op = .neg, .operand = operand },
            });
        }
        return self.parsePrimary();
    }

    /// Parse a primary expression
    /// primary → NUMBER | IDENTIFIER | "(" expression ")"
    fn parsePrimary(self: *Parser) ParseError!*Node {
        switch (self.current.type) {
            .int_literal => {
                const value = std.fmt.parseInt(i64, self.current.lexeme, 10) catch
                    return ParseError.InvalidNumber;
                self.advance();
                return self.createNode(.{ .int_literal = value });
            },
            .float_literal => {
                const value = std.fmt.parseFloat(f64, self.current.lexeme) catch
                    return ParseError.InvalidNumber;
                self.advance();
                return self.createNode(.{ .float_literal = value });
            },
            .identifier => {
                const name = self.current.lexeme;
                self.advance();
                return self.createNode(.{ .variable = name });
            },
            .lparen => {
                self.advance(); // consume '('
                const expr = try self.parseExpression();
                try self.expect(.rparen);
                return expr;
            },
            else => return ParseError.UnexpectedToken,
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "parse simple expression" {
    // Use arena for AST nodes - automatically freed when test ends
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = Parser.init("3 + 5", allocator);
    const ast = try parser.parse();
    _ = ast;
}

test "parse operator precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 3 + 5 * 2 should parse as 3 + (5 * 2)
    var parser = Parser.init("3 + 5 * 2", allocator);
    const ast = try parser.parse();

    // Evaluate to verify precedence
    var vars = std.StringHashMap(f64).init(allocator);
    defer vars.deinit();

    const result = ast.eval(&vars);
    try std.testing.expectEqual(@as(f64, 13), result);
}

test "parse parentheses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // (3 + 5) * 2 should be 16
    var parser = Parser.init("(3 + 5) * 2", allocator);
    const ast = try parser.parse();

    var vars = std.StringHashMap(f64).init(allocator);
    defer vars.deinit();

    const result = ast.eval(&vars);
    try std.testing.expectEqual(@as(f64, 16), result);
}
