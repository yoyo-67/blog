//! Token definitions for Zig subset compiler (simplified)

const std = @import("std");

pub const TokenType = enum {
    // Keywords
    keyword_fn,
    keyword_pub,
    keyword_const,
    keyword_var,
    keyword_return,
    keyword_true,
    keyword_false,

    // Types
    type_i32,
    type_i64,
    type_bool,
    type_void,

    // Literals
    int_literal,

    // Identifiers
    identifier,

    // Operators
    plus, // +
    minus, // -
    star, // *
    slash, // /
    equal, // =

    // Delimiters
    lparen, // (
    rparen, // )
    lbrace, // {
    rbrace, // }
    comma, // ,
    colon, // :
    semicolon, // ;

    // Special
    eof,
    invalid,

    pub fn symbol(self: TokenType) []const u8 {
        return switch (self) {
            .keyword_fn => "fn",
            .keyword_pub => "pub",
            .keyword_const => "const",
            .keyword_var => "var",
            .keyword_return => "return",
            .keyword_true => "true",
            .keyword_false => "false",
            .type_i32 => "i32",
            .type_i64 => "i64",
            .type_bool => "bool",
            .type_void => "void",
            .int_literal => "integer",
            .identifier => "identifier",
            .plus => "+",
            .minus => "-",
            .star => "*",
            .slash => "/",
            .equal => "=",
            .lparen => "(",
            .rparen => ")",
            .lbrace => "{",
            .rbrace => "}",
            .comma => ",",
            .colon => ":",
            .semicolon => ";",
            .eof => "EOF",
            .invalid => "invalid",
        };
    }
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,

    pub fn format(
        self: Token,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}:'{s}'@{d}:{d}", .{
            @tagName(self.type),
            self.lexeme,
            self.line,
            self.column,
        });
    }
};

/// Keyword lookup table
pub const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "fn", .keyword_fn },
    .{ "pub", .keyword_pub },
    .{ "const", .keyword_const },
    .{ "var", .keyword_var },
    .{ "return", .keyword_return },
    .{ "true", .keyword_true },
    .{ "false", .keyword_false },
    .{ "i32", .type_i32 },
    .{ "i64", .type_i64 },
    .{ "bool", .type_bool },
    .{ "void", .type_void },
});

/// Look up keyword or return identifier
pub fn lookupIdentifier(lexeme: []const u8) TokenType {
    return keywords.get(lexeme) orelse .identifier;
}
