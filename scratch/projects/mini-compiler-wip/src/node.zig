pub const Node = union(enum) {
    root: struct {
        decls: []Node,
    },

    int_literal: struct {
        value: i32,
        token_index: usize,
    },

    binary_op: struct {
        lhs: Node,
        op: enum {
            plus,
        },
        rhs: Node,
    },
};
