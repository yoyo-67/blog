const std = @import("std");
const mem = std.mem;

const Token = @import("token.zig");
const Type = @import("types.zig").Type;

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
        token: *const Token,
    },

    identifier: struct {
        name: []const u8,
        value: *const Node,
        token: *const Token,
    },

    identifier_ref: struct {
        name: []const u8,
        token: *const Token,
    },

    unary_op: struct {
        op: Op,
        operand: *const Node,
    },

    return_stmt: struct {
        value: *const Node,
    },

    fn_decl: struct {
        name: []const u8,
        params: []Param,
        block: Block,
        return_type: ?Type,
        token: *const Token,
    },

    pub const Param = struct {
        name: []const u8,
        type: Type,
    };

    pub const Block = struct { decls: []const Node };

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
            .identifier => |iden| {
                try writer.writeAll("identifier(");
                try writer.writeAll("name=");
                try writer.print("{s}", .{iden.name});
                try writer.writeAll(", value=");
                try iden.value.write(writer);
                try writer.writeAll(")");
            },
            .unary_op => |unary| {
                try writer.print("{s}", .{unary.op.symbol()});
                try unary.operand.write(writer);
            },
            .return_stmt => |ret_stmt| {
                try writer.writeAll("return(");
                try writer.writeAll("value=");
                try ret_stmt.value.write(writer);
                try writer.writeAll(")");
            },
            .fn_decl => |fn_decl| {
                try writer.writeAll("fn(");
                try writer.writeAll("name=");
                try writer.print("{s}", .{fn_decl.name});
                try writer.writeAll(", params=");
                if (fn_decl.params.len > 0) {
                    try writer.writeAll("[");
                    for (fn_decl.params, 0..) |param, idx| {
                        if (idx > 0) {
                            try writer.writeAll(", ");
                        }
                        try writer.writeAll("param(");
                        try writer.writeAll("name=");
                        try writer.print("{s}", .{param.name});
                        try writer.writeAll(", type=");
                        try writer.print("{s}", .{@tagName(param.type)});
                        try writer.writeAll(")");
                    }
                    try writer.writeAll("]");
                } else try writer.writeAll("[]");
                try writer.writeAll(", block=");
                for (fn_decl.block.decls) |decl| {
                    try decl.write(writer);
                }
                try writer.writeAll(")");
            },
            .identifier_ref => |val| {
                try writer.print("{s}", .{val.name});
            },
        }
    }
};

pub fn createNode(allocator: mem.Allocator, data: Node) !*Node {
    const node = try allocator.create(Node);
    node.* = data;
    return node;
}
