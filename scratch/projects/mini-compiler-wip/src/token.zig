const std = @import("std");

pub const Token = @This();

type: Type,
lexeme: []const u8,
line: usize = 0,
col: usize = 0,

pub const Loc = struct {
    line: usize,
    col: usize,
};

pub const keywords = std.StaticStringMap(Type).initComptime(.{
    .{ "fn", .kw_fn },
    .{ "const", .kw_const },
    .{ "return", .kw_return },
    .{ "bool", .kw_bool },
    .{ "i32", .kw_i32 },
    .{ "true", .kw_true },
    .{ "false", .kw_false },
});

// Single source of truth for char <-> Type mappings
const char_type_map: []const struct { u8, Type } = &.{
    .{ '+', .plus },
    .{ '-', .minus },
    .{ '*', .star },
    .{ '/', .slash },
    .{ '(', .lpren },
    .{ ')', .rpren },
    .{ '{', .lbrace },
    .{ '}', .rbrace },
    .{ ':', .colon },
    .{ ';', .semicolon },
    .{ ',', .comma },
    .{ '\'', .single_quote },
    .{ '"', .double_quote },
    .{ '=', .equal },
};

pub const Type = enum {
    integer,
    plus,
    eof,
    invalid,
    minus,
    star,
    slash,
    lpren,
    rpren,
    lbrace,
    rbrace,
    colon,
    semicolon,
    comma,
    string,
    single_quote,
    double_quote,
    identifier,
    equal,
    kw_fn,
    kw_return,
    kw_const,
    kw_i32,
    kw_bool,
    kw_true,
    kw_false,

    pub fn toChar(self: Type) ?u8 {
        inline for (char_type_map) |entry| {
            if (self == entry[1]) return entry[0];
        }
        return null;
    }

    pub fn fromChar(c: u8) ?Type {
        inline for (char_type_map) |entry| {
            if (c == entry[0]) return entry[1];
        }
        return null;
    }
};
