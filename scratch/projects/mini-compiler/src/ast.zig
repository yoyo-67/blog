//! Abstract Syntax Tree (AST) definitions for the mini math compiler
//!
//! The AST represents the hierarchical structure of the source code.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Binary operators
pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    mod,

    pub fn symbol(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .mod => "%",
        };
    }
};

/// Unary operators
pub const UnaryOp = enum {
    neg,

    pub fn symbol(self: UnaryOp) []const u8 {
        return switch (self) {
            .neg => "-",
        };
    }
};

/// AST Node - represents all possible node types in the syntax tree
pub const Node = union(enum) {
    /// Integer literal: 42
    int_literal: i64,

    /// Float literal: 3.14
    float_literal: f64,

    /// Binary operation: left op right
    binary: struct {
        op: BinaryOp,
        left: *Node,
        right: *Node,
    },

    /// Unary operation: op operand
    unary: struct {
        op: UnaryOp,
        operand: *Node,
    },

    /// Variable reference: x
    variable: []const u8,

    /// Assignment: name = value
    assignment: struct {
        name: []const u8,
        value: *Node,
    },

    /// List of statements: stmt1; stmt2; stmt3
    statement_list: struct {
        statements: []*Node,
    },

    /// Create a new node allocated with the given allocator
    pub fn create(allocator: Allocator, node: Node) !*Node {
        const ptr = try allocator.create(Node);
        ptr.* = node;
        return ptr;
    }

    /// Pretty print the AST (for debugging)
    pub fn dump(self: *const Node, writer: anytype, indent: usize) !void {
        const spaces = "                                        ";
        const prefix = spaces[0..@min(indent * 2, spaces.len)];

        switch (self.*) {
            .int_literal => |val| try writer.print("{s}Int({d})\n", .{ prefix, val }),
            .float_literal => |val| try writer.print("{s}Float({d})\n", .{ prefix, val }),
            .variable => |name| try writer.print("{s}Var({s})\n", .{ prefix, name }),
            .assignment => |assign| {
                try writer.print("{s}Assign({s})\n", .{ prefix, assign.name });
                try assign.value.dump(writer, indent + 1);
            },
            .unary => |unary| {
                try writer.print("{s}Unary({s})\n", .{ prefix, unary.op.symbol() });
                try unary.operand.dump(writer, indent + 1);
            },
            .binary => |binary| {
                try writer.print("{s}Binary({s})\n", .{ prefix, binary.op.symbol() });
                try binary.left.dump(writer, indent + 1);
                try binary.right.dump(writer, indent + 1);
            },
            .statement_list => |list| {
                try writer.print("{s}Statements\n", .{prefix});
                for (list.statements) |stmt| {
                    try stmt.dump(writer, indent + 1);
                }
            },
        }
    }

    /// Evaluate the AST directly (for testing, without full compilation)
    pub fn eval(self: *const Node, variables: *std.StringHashMap(f64)) f64 {
        return switch (self.*) {
            .int_literal => |val| @floatFromInt(val),
            .float_literal => |val| val,
            .variable => |name| variables.get(name) orelse 0,
            .assignment => |assign| {
                const val = assign.value.eval(variables);
                variables.put(assign.name, val) catch {};
                return val;
            },
            .unary => |unary| switch (unary.op) {
                .neg => -unary.operand.eval(variables),
            },
            .binary => |binary| {
                const left = binary.left.eval(variables);
                const right = binary.right.eval(variables);
                return switch (binary.op) {
                    .add => left + right,
                    .sub => left - right,
                    .mul => left * right,
                    .div => left / right,
                    .mod => @mod(left, right),
                };
            },
            .statement_list => |list| {
                var result: f64 = 0;
                for (list.statements) |stmt| {
                    result = stmt.eval(variables);
                }
                return result;
            },
        };
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

    var vars = std.StringHashMap(f64).init(allocator);
    defer vars.deinit();

    const result = binary.eval(&vars);
    try std.testing.expectEqual(@as(f64, 8), result);
}
