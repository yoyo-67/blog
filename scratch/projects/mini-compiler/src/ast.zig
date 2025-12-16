//! Abstract Syntax Tree (AST) definitions for Zig subset compiler
//!
//! The AST represents the hierarchical structure of the source code.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Type representation in AST (unresolved - just names)
pub const TypeExpr = union(enum) {
    /// Primitive type: i32, u8, bool, void
    primitive: PrimitiveType,
    /// Named type (identifier)
    named: []const u8,
    /// Pointer type: *T
    pointer: *const TypeExpr,
    /// Optional type: ?T
    optional: *const TypeExpr,

    pub const PrimitiveType = enum {
        i8,
        i16,
        i32,
        i64,
        u8,
        u16,
        u32,
        u64,
        f32,
        f64,
        bool,
        void,

        pub fn fromString(s: []const u8) ?PrimitiveType {
            const map = std.StaticStringMap(PrimitiveType).initComptime(.{
                .{ "i8", .i8 },
                .{ "i16", .i16 },
                .{ "i32", .i32 },
                .{ "i64", .i64 },
                .{ "u8", .u8 },
                .{ "u16", .u16 },
                .{ "u32", .u32 },
                .{ "u64", .u64 },
                .{ "f32", .f32 },
                .{ "f64", .f64 },
                .{ "bool", .bool },
                .{ "void", .void },
            });
            return map.get(s);
        }
    };
};

/// Binary operators
pub const BinaryOp = enum {
    // Arithmetic
    add, // +
    sub, // -
    mul, // *
    div, // /
    mod, // %

    // Comparison
    eq, // ==
    neq, // !=
    lt, // <
    lte, // <=
    gt, // >
    gte, // >=

    // Logical
    @"and", // and
    @"or", // or

    pub fn symbol(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .mod => "%",
            .eq => "==",
            .neq => "!=",
            .lt => "<",
            .lte => "<=",
            .gt => ">",
            .gte => ">=",
            .@"and" => "and",
            .@"or" => "or",
        };
    }
};

/// Unary operators
pub const UnaryOp = enum {
    neg, // -
    not, // !

    pub fn symbol(self: UnaryOp) []const u8 {
        return switch (self) {
            .neg => "-",
            .not => "!",
        };
    }
};

/// Assignment operators
pub const AssignOp = enum {
    assign, // =
    add_assign, // +=
    sub_assign, // -=
    mul_assign, // *=
    div_assign, // /=

    pub fn symbol(self: AssignOp) []const u8 {
        return switch (self) {
            .assign => "=",
            .add_assign => "+=",
            .sub_assign => "-=",
            .mul_assign => "*=",
            .div_assign => "/=",
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

    /// If statement: if (cond) then_block else else_block
    if_stmt: struct {
        condition: *Node,
        then_block: *Node,
        else_block: ?*Node,
    },

    /// While loop: while (cond) body
    while_stmt: struct {
        condition: *Node,
        body: *Node,
    },

    /// Break statement
    break_stmt,

    /// Continue statement
    continue_stmt,

    /// Expression statement (expression followed by ;)
    expr_stmt: struct {
        expr: *Node,
    },

    /// Assignment: target = value; or target += value; etc.
    assign_stmt: struct {
        target: *Node,
        op: AssignOp,
        value: *Node,
    },

    // ==================== Expressions ====================

    /// Integer literal: 42
    int_literal: i64,

    /// Float literal: 3.14
    float_literal: f64,

    /// Boolean literal: true, false
    bool_literal: bool,

    /// String literal: "hello"
    string_literal: []const u8,

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
            .root => |root| {
                try writer.print("{s}Root\n", .{prefix});
                for (root.decls) |decl| {
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
            .if_stmt => |if_s| {
                try writer.print("{s}If\n", .{prefix});
                try writer.print("{s}  condition:\n", .{prefix});
                try if_s.condition.dump(writer, indent + 2);
                try writer.print("{s}  then:\n", .{prefix});
                try if_s.then_block.dump(writer, indent + 2);
                if (if_s.else_block) |else_blk| {
                    try writer.print("{s}  else:\n", .{prefix});
                    try else_blk.dump(writer, indent + 2);
                }
            },
            .while_stmt => |while_s| {
                try writer.print("{s}While\n", .{prefix});
                try while_s.condition.dump(writer, indent + 1);
                try while_s.body.dump(writer, indent + 1);
            },
            .break_stmt => try writer.print("{s}Break\n", .{prefix}),
            .continue_stmt => try writer.print("{s}Continue\n", .{prefix}),
            .expr_stmt => |expr_s| {
                try writer.print("{s}ExprStmt\n", .{prefix});
                try expr_s.expr.dump(writer, indent + 1);
            },
            .assign_stmt => |assign| {
                try writer.print("{s}Assign({s})\n", .{ prefix, assign.op.symbol() });
                try assign.target.dump(writer, indent + 1);
                try assign.value.dump(writer, indent + 1);
            },
            .int_literal => |val| try writer.print("{s}Int({d})\n", .{ prefix, val }),
            .float_literal => |val| try writer.print("{s}Float({d})\n", .{ prefix, val }),
            .bool_literal => |val| try writer.print("{s}Bool({any})\n", .{ prefix, val }),
            .string_literal => |val| try writer.print("{s}String(\"{s}\")\n", .{ prefix, val }),
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
