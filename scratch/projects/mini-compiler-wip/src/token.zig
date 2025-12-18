pub const Token = @This();

type: Type,
lexeme: []const u8,

pub const Type = enum {
    integer,
    plus,
    eof,
    invalid,
};
