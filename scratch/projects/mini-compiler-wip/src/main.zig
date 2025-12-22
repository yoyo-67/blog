const std = @import("std");
const lexer = @import("./lexer.zig");
const ast = @import("./ast.zig");
const zir = @import("./zir.zig");

pub fn main() !void {
    _ = lexer;
    _ = ast;
    _ = zir;
}

test {
    std.testing.refAllDecls(@This());
}
