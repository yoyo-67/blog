//! Lexer (Tokenizer) for the mini math compiler
//!
//! Converts source text into a stream of tokens.

const std = @import("std");
const token = @import("token.zig");

pub const Token = token.Token;
pub const TokenType = token.TokenType;

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    start_column: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .start_column = 1,
        };
    }

    /// Look at current character without consuming it
    pub fn peek(self: *Lexer) u8 {
        if (self.pos >= self.source.len) return 0;
        return self.source[self.pos];
    }

    /// Look ahead n characters
    pub fn peekAhead(self: *Lexer, n: usize) u8 {
        const pos = self.pos + n;
        if (pos >= self.source.len) return 0;
        return self.source[pos];
    }

    /// Consume and return current character
    pub fn advance(self: *Lexer) u8 {
        if (self.pos >= self.source.len) return 0;
        const c = self.source[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    /// Skip whitespace characters
    fn skipWhitespace(self: *Lexer) void {
        while (true) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                _ = self.advance();
            } else {
                break;
            }
        }
    }

    /// Check if character is a digit
    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    /// Check if character is alphabetic or underscore
    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    /// Check if character is alphanumeric or underscore
    fn isAlphaNumeric(c: u8) bool {
        return isAlpha(c) or isDigit(c);
    }

    /// Scan a number literal (integer or float)
    fn scanNumber(self: *Lexer) Token {
        const start = self.pos;
        var is_float = false;

        // Scan integer part
        while (isDigit(self.peek())) {
            _ = self.advance();
        }

        // Check for decimal part
        if (self.peek() == '.' and isDigit(self.peekAhead(1))) {
            is_float = true;
            _ = self.advance(); // consume '.'
            while (isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        return .{
            .type = if (is_float) .float_literal else .int_literal,
            .lexeme = self.source[start..self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    /// Scan an identifier
    fn scanIdentifier(self: *Lexer) Token {
        const start = self.pos;

        while (isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }

        return .{
            .type = .identifier,
            .lexeme = self.source[start..self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    /// Get the next token from the source
    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespace();
        self.start_column = self.column;

        if (self.pos >= self.source.len) {
            return .{
                .type = .eof,
                .lexeme = "",
                .line = self.line,
                .column = self.column,
            };
        }

        const c = self.peek();

        // Numbers
        if (isDigit(c)) {
            return self.scanNumber();
        }

        // Identifiers
        if (isAlpha(c)) {
            return self.scanIdentifier();
        }

        // Single character tokens
        _ = self.advance();
        const token_type: TokenType = switch (c) {
            '+' => .plus,
            '-' => .minus,
            '*' => .star,
            '/' => .slash,
            '%' => .percent,
            '(' => .lparen,
            ')' => .rparen,
            ';' => .semicolon,
            '=' => .equals,
            else => .invalid,
        };

        return .{
            .type = token_type,
            .lexeme = self.source[self.pos - 1 .. self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    /// Tokenize entire source into array of tokens
    pub fn tokenize(self: *Lexer, allocator: std.mem.Allocator) ![]Token {
        var tokens: std.ArrayList(Token) = .empty;
        defer tokens.deinit(allocator);

        while (true) {
            const tok = self.nextToken();
            try tokens.append(allocator, tok);
            if (tok.type == .eof) break;
        }

        return tokens.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "lexer basic tokens" {
    var lexer = Lexer.init("3 + 5");

    const t1 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.int_literal, t1.type);
    try std.testing.expectEqualStrings("3", t1.lexeme);

    const t2 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.plus, t2.type);

    const t3 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.int_literal, t3.type);
    try std.testing.expectEqualStrings("5", t3.lexeme);

    const t4 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.eof, t4.type);
}

test "lexer float" {
    var lexer = Lexer.init("3.14");
    const tok = lexer.nextToken();
    try std.testing.expectEqual(TokenType.float_literal, tok.type);
    try std.testing.expectEqualStrings("3.14", tok.lexeme);
}

test "lexer identifier" {
    var lexer = Lexer.init("foo = 42");

    const t1 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.identifier, t1.type);
    try std.testing.expectEqualStrings("foo", t1.lexeme);

    const t2 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.equals, t2.type);

    const t3 = lexer.nextToken();
    try std.testing.expectEqual(TokenType.int_literal, t3.type);
}
