const std = @import("std");
const lexer = @import("./lexer.zig");
const ast = @import("./ast.zig");

pub fn main() !void {
    _ = lexer;
    _ = ast;
}

test {
    std.testing.refAllDecls(@This());
}
