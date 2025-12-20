const std = @import("std");
const mem = std.mem;
pub const Node = union(enum) {
    root: struct {
        decls: []Node,
    },

    int_literal: struct {
        value: i32,
        token_index: usize,
    },

    binary_op: struct {
        lhs: *const Node,
        op: enum {
            plus,
            minus,
            mul,
            div,
        },
        rhs: *const Node,
    },
};

pub fn createNode(allocator: mem.Allocator, data: Node) !*Node {
    const node = try allocator.create(Node);
    node.* = data;
    return node;
}
