//! Abstract Syntax Tree (AST) definitions for Zig subset compiler (simplified)
//!
//! The AST represents the hierarchical structure of the source code.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Type representation in AST (unresolved - just names)
pub const TypeExpr = union(enum) {
    /// Primitive type: i32, i64, bool, void
    primitive: PrimitiveType,
    /// Named type (identifier)
    named: []const u8,

    pub const PrimitiveType = enum {
        i32,
        i64,
        bool,
        void,

        pub fn fromString(s: []const u8) ?PrimitiveType {
            const map = std.StaticStringMap(PrimitiveType).initComptime(.{
                .{ "i32", .i32 },
                .{ "i64", .i64 },
                .{ "bool", .bool },
                .{ "void", .void },
            });
            return map.get(s);
        }
    };
};

/// Binary operators (arithmetic only)
pub const BinaryOp = enum {
    add, // +
    sub, // -
    mul, // *
    div, // /

    pub fn symbol(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
        };
    }
};

/// Unary operators
pub const UnaryOp = enum {
    neg, // -

    pub fn symbol(self: UnaryOp) []const u8 {
        return switch (self) {
            .neg => "-",
        };
    }
};

/// Function parameter
pub const Param = struct {
    name: []const u8,
    type_expr: TypeExpr,
};

/// AST Node - represents all possible node types in the syntax tree
pub const Node = union(enum) {
    // ==================== Top-level declarations ====================

    /// Function declaration: pub fn name(params) ReturnType { body }
    fn_decl: struct {
        is_pub: bool,
        name: []const u8,
        params: []const Param,
        return_type: TypeExpr,
        body: *Node, // block
    },

    /// Constant declaration: const name: Type = value;
    const_decl: struct {
        name: []const u8,
        type_expr: ?TypeExpr, // optional, can be inferred
        value: *Node,
    },

    /// Variable declaration: var name: Type = value;
    var_decl: struct {
        name: []const u8,
        type_expr: ?TypeExpr,
        value: ?*Node, // optional initializer
    },

    // ==================== Statements ====================

    /// Block: { statements... }
    block: struct {
        statements: []*Node,
    },

    /// Return statement: return value;
    return_stmt: struct {
        value: ?*Node,
    },

    /// Expression statement (expression followed by ;)
    expr_stmt: struct {
        expr: *Node,
    },

    // ==================== Expressions ====================

    /// Integer literal: 42
    int_literal: i64,

    /// Boolean literal: true, false
    bool_literal: bool,

    /// Identifier: foo
    identifier: []const u8,

    /// Binary expression: left op right
    binary: struct {
        op: BinaryOp,
        left: *Node,
        right: *Node,
    },

    /// Unary expression: op operand
    unary: struct {
        op: UnaryOp,
        operand: *Node,
    },

    /// Function call: func(args...)
    call: struct {
        callee: *Node,
        args: []*Node,
    },

    /// Grouped expression: (expr)
    grouped: struct {
        expr: *Node,
    },

    // ==================== Special ====================

    /// Root node: contains all top-level declarations
    root: struct {
        decls: []*Node,
    },

    /// Create a new node allocated with the given allocator
    pub fn create(allocator: Allocator, node: Node) !*Node {
        const ptr = try allocator.create(Node);
        ptr.* = node;
        return ptr;
    }

    /// Pretty print the AST (for debugging)
    pub fn dump(self: *const Node, writer: anytype, indent: usize) !void {
        const spaces = "                                                  ";
        const prefix = spaces[0..@min(indent * 2, spaces.len)];

        switch (self.*) {
            .root => |r| {
                try writer.print("{s}Root\n", .{prefix});
                for (r.decls) |decl| {
                    try decl.dump(writer, indent + 1);
                }
            },
            .fn_decl => |func| {
                try writer.print("{s}FnDecl({s}{s})\n", .{
                    prefix,
                    if (func.is_pub) "pub " else "",
                    func.name,
                });
                try writer.print("{s}  params: {d}\n", .{ prefix, func.params.len });
                try func.body.dump(writer, indent + 1);
            },
            .const_decl => |decl| {
                try writer.print("{s}ConstDecl({s})\n", .{ prefix, decl.name });
                try decl.value.dump(writer, indent + 1);
            },
            .var_decl => |decl| {
                try writer.print("{s}VarDecl({s})\n", .{ prefix, decl.name });
                if (decl.value) |val| {
                    try val.dump(writer, indent + 1);
                }
            },
            .block => |blk| {
                try writer.print("{s}Block\n", .{prefix});
                for (blk.statements) |stmt| {
                    try stmt.dump(writer, indent + 1);
                }
            },
            .return_stmt => |ret| {
                try writer.print("{s}Return\n", .{prefix});
                if (ret.value) |val| {
                    try val.dump(writer, indent + 1);
                }
            },
            .expr_stmt => |expr_s| {
                try writer.print("{s}ExprStmt\n", .{prefix});
                try expr_s.expr.dump(writer, indent + 1);
            },
            .int_literal => |val| try writer.print("{s}Int({d})\n", .{ prefix, val }),
            .bool_literal => |val| try writer.print("{s}Bool({any})\n", .{ prefix, val }),
            .identifier => |name| try writer.print("{s}Ident({s})\n", .{ prefix, name }),
            .binary => |bin| {
                try writer.print("{s}Binary({s})\n", .{ prefix, bin.op.symbol() });
                try bin.left.dump(writer, indent + 1);
                try bin.right.dump(writer, indent + 1);
            },
            .unary => |un| {
                try writer.print("{s}Unary({s})\n", .{ prefix, un.op.symbol() });
                try un.operand.dump(writer, indent + 1);
            },
            .call => |c| {
                try writer.print("{s}Call\n", .{prefix});
                try c.callee.dump(writer, indent + 1);
                for (c.args) |arg| {
                    try arg.dump(writer, indent + 1);
                }
            },
            .grouped => |g| {
                try writer.print("{s}Grouped\n", .{prefix});
                try g.expr.dump(writer, indent + 1);
            },
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ast creation" {
    const allocator = std.testing.allocator;

    // Create: 3 + 5
    const left = try Node.create(allocator, .{ .int_literal = 3 });
    defer allocator.destroy(left);

    const right = try Node.create(allocator, .{ .int_literal = 5 });
    defer allocator.destroy(right);

    const binary = try Node.create(allocator, .{
        .binary = .{ .op = .add, .left = left, .right = right },
    });
    defer allocator.destroy(binary);

    try std.testing.expectEqual(BinaryOp.add, binary.binary.op);
}

test "primitive type from string" {
    try std.testing.expectEqual(TypeExpr.PrimitiveType.i32, TypeExpr.PrimitiveType.fromString("i32"));
    try std.testing.expectEqual(TypeExpr.PrimitiveType.bool, TypeExpr.PrimitiveType.fromString("bool"));
    try std.testing.expectEqual(@as(?TypeExpr.PrimitiveType, null), TypeExpr.PrimitiveType.fromString("foo"));
}
