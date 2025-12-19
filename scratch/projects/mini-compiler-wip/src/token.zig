pub const Token = @This();

type: Type,
lexeme: []const u8,

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
