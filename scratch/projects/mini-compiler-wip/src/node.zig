const std = @import("std");
const mem = std.mem;

pub const Op = enum {
    plus,
    minus,
    mul,
    div,

    pub fn symbol(self: Op) []const u8 {
        return switch (self) {
            .plus => "+",
            .minus => "-",
            .mul => "*",
            .div => "/",
        };
    }
};

pub const Node = union(enum) {
    root: struct {
        decls: []Node,
    },

    int_literal: struct {
        value: i32,
    },

    binary_op: struct {
        lhs: *const Node,
        op: Op,
        rhs: *const Node,
    },

    pub fn toString(self: Node, allocator: mem.Allocator) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        try self.write(&buf.writer(allocator));
        return try buf.toOwnedSlice(allocator);
    }

    fn write(self: Node, writer: anytype) !void {
        switch (self) {
            .int_literal => |ltr| try writer.print("{d}", .{ltr.value}),
            .binary_op => |bin| {
                try writer.writeAll("(");
                try bin.lhs.write(writer);
                try writer.print(" {s} ", .{bin.op.symbol()});
                try bin.rhs.write(writer);
                try writer.writeAll(")");
            },
            .root => |root| {
                for (root.decls, 0..) |decl, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try decl.write(writer);
                }
            },
        }
    }
};

pub fn createNode(allocator: mem.Allocator, data: Node) !*Node {
    const node = try allocator.create(Node);
    node.* = data;
    return node;
}
