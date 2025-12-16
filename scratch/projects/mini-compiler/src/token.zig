//! Token definitions for Zig subset compiler

const std = @import("std");

pub const TokenType = enum {
    // Keywords
    keyword_fn,
    keyword_pub,
    keyword_const,
    keyword_var,
    keyword_return,
    keyword_if,
    keyword_else,
    keyword_while,
    keyword_for,
    keyword_break,
    keyword_continue,
    keyword_and,
    keyword_or,
    keyword_true,
    keyword_false,
    keyword_undefined,

    // Types
    type_i8,
    type_i16,
    type_i32,
    type_i64,
    type_u8,
    type_u16,
    type_u32,
    type_u64,
    type_f32,
    type_f64,
    type_bool,
    type_void,

    // Literals
    int_literal,
    float_literal,
    string_literal,
    char_literal,

    // Identifiers
    identifier,

    // Operators
    plus, // +
    minus, // -
    star, // *
    slash, // /
    percent, // %
    equal, // =
    equal_equal, // ==
    bang, // !
    bang_equal, // !=
    less, // <
    less_equal, // <=
    greater, // >
    greater_equal, // >=
    plus_equal, // +=
    minus_equal, // -=
    star_equal, // *=
    slash_equal, // /=

    // Delimiters
    lparen, // (
    rparen, // )
    lbrace, // {
    rbrace, // }
    lbracket, // [
    rbracket, // ]
    comma, // ,
    colon, // :
    semicolon, // ;
    dot, // .
    arrow, // ->
    at, // @

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
            .keyword_if => "if",
            .keyword_else => "else",
            .keyword_while => "while",
            .keyword_for => "for",
            .keyword_break => "break",
            .keyword_continue => "continue",
            .keyword_and => "and",
            .keyword_or => "or",
            .keyword_true => "true",
            .keyword_false => "false",
            .keyword_undefined => "undefined",
            .type_i8 => "i8",
            .type_i16 => "i16",
            .type_i32 => "i32",
            .type_i64 => "i64",
            .type_u8 => "u8",
            .type_u16 => "u16",
            .type_u32 => "u32",
            .type_u64 => "u64",
            .type_f32 => "f32",
            .type_f64 => "f64",
            .type_bool => "bool",
            .type_void => "void",
            .int_literal => "integer",
            .float_literal => "float",
            .string_literal => "string",
            .char_literal => "char",
            .identifier => "identifier",
            .plus => "+",
            .minus => "-",
            .star => "*",
            .slash => "/",
            .percent => "%",
            .equal => "=",
            .equal_equal => "==",
            .bang => "!",
            .bang_equal => "!=",
            .less => "<",
            .less_equal => "<=",
            .greater => ">",
            .greater_equal => ">=",
            .plus_equal => "+=",
            .minus_equal => "-=",
            .star_equal => "*=",
            .slash_equal => "/=",
            .lparen => "(",
            .rparen => ")",
            .lbrace => "{",
            .rbrace => "}",
            .lbracket => "[",
            .rbracket => "]",
            .comma => ",",
            .colon => ":",
            .semicolon => ";",
            .dot => ".",
            .arrow => "->",
            .at => "@",
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
    .{ "if", .keyword_if },
    .{ "else", .keyword_else },
    .{ "while", .keyword_while },
    .{ "for", .keyword_for },
    .{ "break", .keyword_break },
    .{ "continue", .keyword_continue },
    .{ "and", .keyword_and },
    .{ "or", .keyword_or },
    .{ "true", .keyword_true },
    .{ "false", .keyword_false },
    .{ "undefined", .keyword_undefined },
    .{ "i8", .type_i8 },
    .{ "i16", .type_i16 },
    .{ "i32", .type_i32 },
    .{ "i64", .type_i64 },
    .{ "u8", .type_u8 },
    .{ "u16", .type_u16 },
    .{ "u32", .type_u32 },
    .{ "u64", .type_u64 },
    .{ "f32", .type_f32 },
    .{ "f64", .type_f64 },
    .{ "bool", .type_bool },
    .{ "void", .type_void },
});

/// Look up keyword or return identifier
pub fn lookupIdentifier(lexeme: []const u8) TokenType {
    return keywords.get(lexeme) orelse .identifier;
}
