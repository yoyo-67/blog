const std = @import("std");
const mem = std.mem;

pub const Type = enum {
    i32,
    bool,
    void,
    identifer,

    pub fn fromString(s: []const u8) Type {
        if (mem.eql(u8, s, "i32")) return .i32;
        if (mem.eql(u8, s, "bool")) return .bool;
        if (mem.eql(u8, s, "void")) return .void;
        return .identifer;
    }
};
