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

fn checkIsAlpha(c: u8) bool {
    return c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z' or c == '_';
}

fn checkIsAlphaNumeric(c: u8) bool {
    return checkIsAlpha(c) or checkIsDigit(c);
}

fn getText(self: *Lexer, startPos: usize) []const u8 {
    return self.source[startPos..self.pos];
}

fn makeToken(self: *Lexer, startPos: usize, tokenType: Token.Type) Token {
    return .{
        .lexeme = self.getText(startPos),
        .type = tokenType,
    };
}

fn expectChar(self: *Lexer, expected: u8) void {
    if (self.peek() != expected) unreachable;
}

fn checkTokenType(self: *Lexer, tokenType: Token.Type) bool {
    const expected = tokenType.toChar() orelse return false;
    return self.peek() == expected;
}

fn expectTokenType(self: *Lexer, tokenType: Token.Type) void {
    if (!self.checkTokenType(tokenType)) unreachable;
}

fn checkOneOf(self: *Lexer, comptime types: []const Token.Type) bool {
    inline for (types) |t| {
        if (self.checkTokenType(t)) return true;
    }
    return false;
}

fn expectOneOf(self: *Lexer, comptime types: []const Token.Type) void {
    inline for (types) |t| {
        if (self.checkTokenType(t)) return;
    }
    unreachable;
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

    if (self.checkOneOf(&.{ .double_quote, .single_quote })) {
        return self.scanQuotedString();
    }

    if (checkIsAlpha(c)) {
        return self.scanIdentifier();
    }

    self.advance();

    switch (c) {
        '+' => return self.makeToken(startPos, .plus),
        '-' => return self.makeToken(startPos, .minus),
        '*' => return self.makeToken(startPos, .star),
        '/' => return self.makeToken(startPos, .slash),
        '(' => return self.makeToken(startPos, .lpren),
        ')' => return self.makeToken(startPos, .rpren),
        '{' => return self.makeToken(startPos, .lbrace),
        '}' => return self.makeToken(startPos, .rbrace),
        ':' => return self.makeToken(startPos, .colon),
        ';' => return self.makeToken(startPos, .semicolon),
        '=' => return self.makeToken(startPos, .equal),
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

fn scanQuotedString(self: *Lexer) Token {
    self.expectOneOf(&.{ .single_quote, .double_quote });
    const openingQuote = self.peek();
    const startPos = self.pos;
    self.advance();

    while (self.peek() != openingQuote and !self.checkIsAtEnd()) {
        self.advance();
    }

    if (self.checkIsAtEnd()) {
        return self.makeToken(startPos, .invalid);
    }

    self.expectChar(openingQuote);
    self.advance();
    const token = self.makeToken(startPos, .string);
    return token;
}

fn scanIdentifier(self: *Lexer) Token {
    const startPos = self.pos;

    while (checkIsAlphaNumeric(self.peek())) {
        self.advance();
    }

    if (Token.keywords.get(self.getText(startPos))) |kw| {
        return self.makeToken(startPos, kw);
    }

    const token = self.makeToken(startPos, .identifier);
    return token;
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

test "digits" {
    const allocator = std.testing.allocator;
    const source = "45 3+ 0";

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .integer, .lexeme = "45" },
        .{ .type = .integer, .lexeme = "3" },
        .{ .type = .plus, .lexeme = "+" },
        .{ .type = .integer, .lexeme = "0" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}

test "strings" {
    const allocator = std.testing.allocator;
    const source =
        \\ "hello" "world"
        \\ ""
        \\ "hello world"
    ;

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .string, .lexeme = "\"hello\"" },
        .{ .type = .string, .lexeme = "\"world\"" },
        .{ .type = .string, .lexeme = "\"\"" },
        .{ .type = .string, .lexeme = "\"hello world\"" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}

test "unclosed double quote string returns invalid" {
    const allocator = std.testing.allocator;
    const source = "\"hello";

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .invalid, .lexeme = "\"hello" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}

test "unclosed single quote string returns invalid" {
    const allocator = std.testing.allocator;
    const source = "'hello";

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .invalid, .lexeme = "'hello" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}

test "mismatched quotes returns invalid" {
    const allocator = std.testing.allocator;
    const source = "\"hello'";

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .invalid, .lexeme = "\"hello'" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}

test "identifier" {
    const allocator = std.testing.allocator;
    const source = "_foo12 bar+ baz x2";

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .identifier, .lexeme = "_foo12" },
        .{ .type = .identifier, .lexeme = "bar" },
        .{ .type = .plus, .lexeme = "+" },
        .{ .type = .identifier, .lexeme = "baz" },
        .{ .type = .identifier, .lexeme = "x2" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}

test "keyworks" {
    const allocator = std.testing.allocator;
    const source = "fn hello const return i32 bool";

    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .type = .kw_fn, .lexeme = "fn" },
        .{ .type = .identifier, .lexeme = "hello" },
        .{ .type = .kw_const, .lexeme = "const" },
        .{ .type = .kw_return, .lexeme = "return" },
        .{ .type = .kw_i32, .lexeme = "i32" },
        .{ .type = .kw_bool, .lexeme = "bool" },
        .{ .type = .eof, .lexeme = "" },
    };

    for (tokens, 0..) |token, i| {
        try expect(token.type, expected[i].type);
        try expectString(token.lexeme, expected[i].lexeme);
    }
}
