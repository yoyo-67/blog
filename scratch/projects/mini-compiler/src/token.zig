//! Token definitions for the mini math compiler

pub const TokenType = enum {
    // Literals
    int_literal,
    float_literal,

    // Operators
    plus, // +
    minus, // -
    star, // *
    slash, // /
    percent, // %

    // Delimiters
    lparen, // (
    rparen, // )
    semicolon, // ;
    equals, // =

    // Other
    identifier,
    eof,
    invalid,

    pub fn symbol(self: TokenType) []const u8 {
        return switch (self) {
            .int_literal => "integer",
            .float_literal => "float",
            .plus => "+",
            .minus => "-",
            .star => "*",
            .slash => "/",
            .percent => "%",
            .lparen => "(",
            .rparen => ")",
            .semicolon => ";",
            .equals => "=",
            .identifier => "identifier",
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

const std = @import("std");
