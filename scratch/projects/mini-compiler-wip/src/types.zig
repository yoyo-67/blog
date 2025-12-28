const std = @import("std");
const mem = std.mem;

pub const Type = enum {
    i32,
    bool,
    void,
    identifer,
    undefined,

    pub fn fromString(s: []const u8) Type {
        if (mem.eql(u8, s, "i32")) return .i32;
        if (mem.eql(u8, s, "bool")) return .bool;
        if (mem.eql(u8, s, "void")) return .void;
        return .identifer;
    }
};

/// Single source of truth for literal values
pub const Value = union(enum) {
    int: i32,
    boolean: bool,

    pub fn getType(self: Value) Type {
        return switch (self) {
            .int => .i32,
            .boolean => .bool,
        };
    }

    pub fn format(self: Value, writer: anytype) !void {
        switch (self) {
            .int => |v| try writer.print("{d}", .{v}),
            .boolean => |v| try writer.print("{}", .{v}),
        }
    }
};
