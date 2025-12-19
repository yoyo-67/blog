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

fn checkIsDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn makeToken(self: *Lexer, startPos: usize, tokenType: Token.Type) Token {
    return .{
        .lexeme = self.source[startPos..self.pos],
        .type = tokenType,
    };
}

// Private helpers - higher level

fn skipWhiteSpace(self: *Lexer) void {
    while (true) {
        const c = self.peek();
        if (c == ' ' or c == '\n' or c == '\t') {
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

    if (checkIsDigit(c)) {
        return self.scanNumber();
    }

    self.advance();

    switch (c) {
        '+' => return self.makeToken(startPos, .plus),
        '-' => return self.makeToken(startPos, .minus),
        '*' => return self.makeToken(startPos, .star),
        '(' => return self.makeToken(startPos, .lpren),
        ')' => return self.makeToken(startPos, .rpren),
        ':' => return self.makeToken(startPos, .colon),
        ';' => return self.makeToken(startPos, .semicolon),
        else => return self.makeToken(startPos, .invalid),
    }
}

fn scanNumber(self: *Lexer) Token {
    const startPos = self.pos;
    while (checkIsDigit(self.peek())) {
        self.advance();
    }
    return self.makeToken(startPos, .integer);
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
        \\12 + 312 + 3
    ;

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const token1 = tokens[0];
    try expect(token1.type, .integer);
    try expectString(token1.lexeme, "12");

    const token2 = tokens[1];
    try expect(token2.type, .plus);
    try expectString(token2.lexeme, "+");

    const token3 = tokens[2];
    try expect(token3.type, .integer);
    try expectString(token3.lexeme, "312");
}

test "+-*" {
    const allocator = std.testing.allocator;
    const source =
        \\ + - * ( )   
        \\ $
    ;

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .plus, .lexeme = "+" },
        .{ .type = .minus, .lexeme = "-" },
        .{ .type = .star, .lexeme = "*" },
        .{ .type = .lpren, .lexeme = "(" },
        .{ .type = .rpren, .lexeme = ")" },
        .{ .type = .invalid, .lexeme = "$" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}

test "empty" {
    const allocator = std.testing.allocator;
    const source =
        \\
    ;

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}

test "special" {
    const allocator = std.testing.allocator;
    const source = "() \n \t $";

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .lpren, .lexeme = "(" },
        .{ .type = .rpren, .lexeme = ")" },
        .{ .type = .invalid, .lexeme = "$" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}
