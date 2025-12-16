//! Lexer (Tokenizer) for Zig subset compiler
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

    /// Skip whitespace and comments
    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (true) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                _ = self.advance();
            } else if (c == '/' and self.peekAhead(1) == '/') {
                // Single-line comment
                while (self.peek() != '\n' and self.peek() != 0) {
                    _ = self.advance();
                }
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

    /// Scan an identifier or keyword
    fn scanIdentifier(self: *Lexer) Token {
        const start = self.pos;

        while (isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }

        const lexeme = self.source[start..self.pos];
        return .{
            .type = token.lookupIdentifier(lexeme),
            .lexeme = lexeme,
            .line = self.line,
            .column = self.start_column,
        };
    }

    /// Scan a string literal
    fn scanString(self: *Lexer) Token {
        const start = self.pos;
        _ = self.advance(); // consume opening "

        while (self.peek() != '"' and self.peek() != 0) {
            if (self.peek() == '\\') {
                _ = self.advance(); // skip escape char
            }
            _ = self.advance();
        }

        if (self.peek() == '"') {
            _ = self.advance(); // consume closing "
        }

        return .{
            .type = .string_literal,
            .lexeme = self.source[start..self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    /// Scan a char literal
    fn scanChar(self: *Lexer) Token {
        const start = self.pos;
        _ = self.advance(); // consume opening '

        if (self.peek() == '\\') {
            _ = self.advance(); // skip escape char
        }
        _ = self.advance(); // consume char

        if (self.peek() == '\'') {
            _ = self.advance(); // consume closing '
        }

        return .{
            .type = .char_literal,
            .lexeme = self.source[start..self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    /// Make a token from current position
    fn makeToken(self: *Lexer, token_type: TokenType, len: usize) Token {
        const start = self.pos;
        for (0..len) |_| {
            _ = self.advance();
        }
        return .{
            .type = token_type,
            .lexeme = self.source[start..self.pos],
            .line = self.line,
            .column = self.start_column,
        };
    }

    /// Get the next token from the source
    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();
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

        // Identifiers and keywords
        if (isAlpha(c)) {
            return self.scanIdentifier();
        }

        // String literals
        if (c == '"') {
            return self.scanString();
        }

        // Char literals
        if (c == '\'') {
            return self.scanChar();
        }

        // Multi-character operators
        const next = self.peekAhead(1);

        switch (c) {
            '=' => {
                if (next == '=') return self.makeToken(.equal_equal, 2);
                return self.makeToken(.equal, 1);
            },
            '!' => {
                if (next == '=') return self.makeToken(.bang_equal, 2);
                return self.makeToken(.bang, 1);
            },
            '<' => {
                if (next == '=') return self.makeToken(.less_equal, 2);
                return self.makeToken(.less, 1);
            },
            '>' => {
                if (next == '=') return self.makeToken(.greater_equal, 2);
                return self.makeToken(.greater, 1);
            },
            '+' => {
                if (next == '=') return self.makeToken(.plus_equal, 2);
                return self.makeToken(.plus, 1);
            },
            '-' => {
                if (next == '>') return self.makeToken(.arrow, 2);
                if (next == '=') return self.makeToken(.minus_equal, 2);
                return self.makeToken(.minus, 1);
            },
            '*' => {
                if (next == '=') return self.makeToken(.star_equal, 2);
                return self.makeToken(.star, 1);
            },
            '/' => {
                if (next == '=') return self.makeToken(.slash_equal, 2);
                return self.makeToken(.slash, 1);
            },
            '%' => return self.makeToken(.percent, 1),
            '(' => return self.makeToken(.lparen, 1),
            ')' => return self.makeToken(.rparen, 1),
            '{' => return self.makeToken(.lbrace, 1),
            '}' => return self.makeToken(.rbrace, 1),
            '[' => return self.makeToken(.lbracket, 1),
            ']' => return self.makeToken(.rbracket, 1),
            ',' => return self.makeToken(.comma, 1),
            ':' => return self.makeToken(.colon, 1),
            ';' => return self.makeToken(.semicolon, 1),
            '.' => return self.makeToken(.dot, 1),
            '@' => return self.makeToken(.at, 1),
            else => return self.makeToken(.invalid, 1),
        }
    }

    /// Tokenize entire source into array of tokens
    pub fn tokenize(self: *Lexer, allocator: std.mem.Allocator) ![]Token {
        var tokens: std.ArrayListUnmanaged(Token) = .empty;
        errdefer tokens.deinit(allocator);

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

test "lexer keywords" {
    var lexer = Lexer.init("fn pub const var return if else while");

    try std.testing.expectEqual(TokenType.keyword_fn, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.keyword_pub, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.keyword_const, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.keyword_var, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.keyword_return, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.keyword_if, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.keyword_else, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.keyword_while, lexer.nextToken().type);
}

test "lexer types" {
    var lexer = Lexer.init("i32 u8 bool void");

    try std.testing.expectEqual(TokenType.type_i32, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.type_u8, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.type_bool, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.type_void, lexer.nextToken().type);
}

test "lexer operators" {
    var lexer = Lexer.init("+ - * / == != <= >= += -=");

    try std.testing.expectEqual(TokenType.plus, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.minus, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.star, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.slash, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.equal_equal, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.bang_equal, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.less_equal, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.greater_equal, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.plus_equal, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.minus_equal, lexer.nextToken().type);
}

test "lexer function declaration" {
    var lexer = Lexer.init("pub fn add(a: i32, b: i32) i32 { return a + b; }");

    try std.testing.expectEqual(TokenType.keyword_pub, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.keyword_fn, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.identifier, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.lparen, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.identifier, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.colon, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.type_i32, lexer.nextToken().type);
}

test "lexer comments" {
    var lexer = Lexer.init(
        \\// this is a comment
        \\const x = 5;
    );

    try std.testing.expectEqual(TokenType.keyword_const, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.identifier, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.equal, lexer.nextToken().type);
    try std.testing.expectEqual(TokenType.int_literal, lexer.nextToken().type);
}
