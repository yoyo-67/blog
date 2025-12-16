//! Semantic Analysis for the mini math compiler
//!
//! Performs type checking and validates variable references.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");

pub const Node = ast_mod.Node;

/// Value types in our language
pub const ValueType = enum {
    int,
    float,

    pub fn format(
        self: ValueType,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(@tagName(self));
    }
};

/// A node annotated with its type
pub const TypedNode = struct {
    node: *Node,
    value_type: ValueType,
};

pub const SemanticError = error{
    UndefinedVariable,
    OutOfMemory,
};

/// Semantic analyzer - tracks variable types and validates the AST
pub const Analyzer = struct {
    /// Map of variable names to their types
    variables: std.StringHashMap(ValueType),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Analyzer {
        return .{
            .variables = std.StringHashMap(ValueType).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Analyzer) void {
        self.variables.deinit();
    }

    /// Analyze an AST node and return its type
    pub fn analyze(self: *Analyzer, node: *Node) SemanticError!TypedNode {
        switch (node.*) {
            .int_literal => {
                return .{ .node = node, .value_type = .int };
            },

            .float_literal => {
                return .{ .node = node, .value_type = .float };
            },

            .variable => |name| {
                if (self.variables.get(name)) |vtype| {
                    return .{ .node = node, .value_type = vtype };
                }
                return SemanticError.UndefinedVariable;
            },

            .assignment => |assign| {
                const typed_value = try self.analyze(assign.value);
                self.variables.put(assign.name, typed_value.value_type) catch
                    return SemanticError.OutOfMemory;
                return .{ .node = node, .value_type = typed_value.value_type };
            },

            .unary => |unary| {
                const typed_operand = try self.analyze(unary.operand);
                return .{ .node = node, .value_type = typed_operand.value_type };
            },

            .binary => |binary| {
                const typed_left = try self.analyze(binary.left);
                const typed_right = try self.analyze(binary.right);

                // Type coercion: if either is float, result is float
                const result_type: ValueType =
                    if (typed_left.value_type == .float or typed_right.value_type == .float)
                    .float
                else
                    .int;

                return .{ .node = node, .value_type = result_type };
            },

            .statement_list => |list| {
                var last_type: ValueType = .int;
                for (list.statements) |stmt| {
                    const typed = try self.analyze(stmt);
                    last_type = typed.value_type;
                }
                return .{ .node = node, .value_type = last_type };
            },
        }
    }

    /// Check if a variable is defined
    pub fn isDefined(self: *const Analyzer, name: []const u8) bool {
        return self.variables.contains(name);
    }

    /// Get the type of a variable (if defined)
    pub fn getType(self: *const Analyzer, name: []const u8) ?ValueType {
        return self.variables.get(name);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "analyze int literal" {
    const allocator = std.testing.allocator;

    const node = try Node.create(allocator, .{ .int_literal = 42 });
    defer allocator.destroy(node);

    var analyzer = Analyzer.init(allocator);
    defer analyzer.deinit();

    const typed = try analyzer.analyze(node);
    try std.testing.expectEqual(ValueType.int, typed.value_type);
}

test "analyze float literal" {
    const allocator = std.testing.allocator;

    const node = try Node.create(allocator, .{ .float_literal = 3.14 });
    defer allocator.destroy(node);

    var analyzer = Analyzer.init(allocator);
    defer analyzer.deinit();

    const typed = try analyzer.analyze(node);
    try std.testing.expectEqual(ValueType.float, typed.value_type);
}

test "analyze undefined variable" {
    const allocator = std.testing.allocator;

    const node = try Node.create(allocator, .{ .variable = "x" });
    defer allocator.destroy(node);

    var analyzer = Analyzer.init(allocator);
    defer analyzer.deinit();

    const result = analyzer.analyze(node);
    try std.testing.expectError(SemanticError.UndefinedVariable, result);
}

test "analyze type coercion" {
    const allocator = std.testing.allocator;

    // int + float = float
    const left = try Node.create(allocator, .{ .int_literal = 3 });
    defer allocator.destroy(left);

    const right = try Node.create(allocator, .{ .float_literal = 5.0 });
    defer allocator.destroy(right);

    const binary = try Node.create(allocator, .{
        .binary = .{ .op = .add, .left = left, .right = right },
    });
    defer allocator.destroy(binary);

    var analyzer = Analyzer.init(allocator);
    defer analyzer.deinit();

    const typed = try analyzer.analyze(binary);
    try std.testing.expectEqual(ValueType.float, typed.value_type);
}
