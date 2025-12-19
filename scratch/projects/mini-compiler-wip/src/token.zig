const std = @import("std");

pub const Token = @This();

type: Type,
lexeme: []const u8,

pub const keywords = std.StaticStringMap(Type).initComptime(.{
    .{ "fn", .kw_fn },
    .{ "const", .kw_const },
    .{ "return", .kw_return },
    .{ "bool", .kw_bool },
    .{ "i32", .kw_i32 },
});

pub const Type = enum {
    integer,
    plus,
    eof,
    invalid,
    minus,
    star,
    lpren,
    rpren,
    colon,
    semicolon,
    string,
    single_quote,
    double_quote,
    identifier,
    kw_fn,
    kw_return,
    kw_const,
    kw_i32,
    kw_bool,

    pub fn toChar(self: Type) ?u8 {
        return switch (self) {
            .plus => '+',
            .minus => '-',
            .star => '*',
            .lpren => '(',
            .rpren => ')',
            .colon => ':',
            .semicolon => ';',
            .single_quote => '\'',
            .double_quote => '"',
            else => null,
        };
    }
};
