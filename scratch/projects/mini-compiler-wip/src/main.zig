const std = @import("std");
const lexer = @import("./lexer.zig");

pub fn main() !void {
    _ = lexer;
}

test {
    std.testing.refAllDecls(@This());
}
