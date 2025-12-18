const std = @import("std");
const ast = @import("./ast.zig");

pub fn main() !void {
    _ = ast;
}

test {
    std.testing.refAllDecls(@This());
}
