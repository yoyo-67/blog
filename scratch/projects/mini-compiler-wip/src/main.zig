const std = @import("std");
const lexer = @import("./lexer.zig");
const ast = @import("./ast.zig");
const zir = @import("./zir.zig");
const sema_mod = @import("sema.zig");

pub fn main() !void {
    _ = lexer;
    _ = ast;
    _ = zir;
    _ = sema_mod;
}

test {
    std.testing.refAllDecls(@This());
}
