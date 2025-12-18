const std = @import("std");
const mem = std.mem;

const expect = std.testing.expectEqual;
const expectString = std.testing.expectEqualStrings;

const Token = @import("token.zig");

pub const Lexer = @This();

source: []const u8,
pos: usize,
line: usize,
column: usize,

// Public methods

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

// Private helpers - low level

fn checkIsAtEnd(self: *Lexer) bool {
    return self.pos == self.source.len;
}

fn peek(self: *Lexer) u8 {
    if (self.checkIsAtEnd()) return 0;
    return self.source[self.pos];
}

fn advance(self: *Lexer) void {
    self.pos += 1;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

// Private helpers - higher level

fn skipWhiteSpace(self: *Lexer) void {
    while (true) {
        if (self.peek() == ' ') {
            self.advance();
        } else {
            break;
        }
    }
}

fn nextToken(self: *Lexer) Token {
    self.skipWhiteSpace();
    const startPos = self.pos;
    if (self.pos == self.source.len) {
        return Token{
            .type = .eof,
            .lexeme = "",
        };
    }
    const c = self.peek();
    self.advance();

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

// Tests

test "start lexering" {
    const source: [:0]const u8 =
        \\Hello World
    ;

    const lexer = Lexer.init(source);
    try expectString(lexer.source, "Hello World");
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
    defer allocator.free(tokens);

    const token1 = tokens[0];
    try expect(token1.type, .integer);
    try expectString(token1.lexeme, "1");

    const token2 = tokens[1];
    try expect(token2.type, .plus);
    try expectString(token2.lexeme, "+");

    const token3 = tokens[2];
    try expect(token3.type, .integer);
    try expectString(token3.lexeme, "3");
}
