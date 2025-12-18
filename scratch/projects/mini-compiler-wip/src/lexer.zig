const std = @import("std");
const mem = std.mem;

const expect = std.testing.expectEqual;

pub const Lexer = @This();

const Token = struct {
    type: TokenType,
    lexeme: []const u8,

    const TokenType = enum {
        integer,
        plus,
        eof,
    };
};

source: []const u8,
pos: usize,
line: usize,
column: usize,

pub fn init(source: []const u8) Lexer {
    return Lexer{
        .pos = 0,
        .line = 1,
        .column = 1,
        .source = source,
    };
}

pub fn tokenize(self: *Lexer, allocator: mem.Allocator) ![]const Token {
    var tokens: std.ArrayListUnmanaged(Token) = .empty;

    while (true) {
        const token = self.nextToken();
        try tokens.append(allocator, token);
        if (token.type == .eof) break;
    }

    return tokens.toOwnedSlice(allocator);
}

fn nextToken(self: *Lexer) Token {
    const startPos = self.pos;
    self.skipWhiteSpace();
    if (self.pos == self.source.len) {
        return Token{
            .type = .eof,
            .lexeme = "",
        };
    }
    // get the char
    const c = self.peek();
    //
    // increment the pos
    self.advance();

    // if c.type
    //
    if (isDigit(c)) {
        return .{
            .lexeme = self.source[startPos..self.pos],
            .type = .integer,
        };
    }

    return Token{
        .lexeme = "+",
        .type = .plus,
    };
}

fn skipWhiteSpace(self: *Lexer) void {
    while (true) {
        if (self.peek() == ' ') {
            self.advance();
        } else {
            break;
        }
    }
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn checkIsAtEnd(self: *Lexer) bool {
    return self.pos == self.source.len;
}

fn advance(self: *Lexer) void {
    self.pos += 1;
}

fn peek(self: *Lexer) u8 {
    if (self.checkIsAtEnd()) return 0;
    return self.source[self.pos];
}

test "start lexering" {
    const allocator = std.testing.allocator;
    _ = allocator; // autofix

    const source: [:0]const u8 =
        \\Hello World
    ;

    const lexer = Lexer.init(source);
    try expect(lexer.source, "Hello World");
    try expect(lexer.pos, 0);
    try expect(lexer.line, 1);
    try expect(lexer.column, 1);
}

test "tokens" {
    const allocator = std.testing.allocator;
    const source =
        \\1 + 3
    ;

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);

    const token1 = tokens[0];
    try expect(token1.type, .integer);
    try expect(token1.lexeme, "1");

    const token2 = tokens[1];
    try expect(token2.type, .plus);
    try expect(token2.lexeme, "+");

    const token3 = tokens[2];
    try expect(token3.type, .integer);
    try expect(token3.lexeme, "2");
}
