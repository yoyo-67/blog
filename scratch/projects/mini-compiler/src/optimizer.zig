//! Optimizer for the mini math compiler
//!
//! Performs constant folding - evaluating constant expressions at compile time.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");

pub const Node = ast_mod.Node;
pub const BinaryOp = ast_mod.BinaryOp;

pub const OptimizeError = error{
    OutOfMemory,
};

/// AST Optimizer
pub const Optimizer = struct {
    allocator: Allocator,
    /// Count of optimizations performed
    optimizations_count: usize,

    pub fn init(allocator: Allocator) Optimizer {
        return .{
            .allocator = allocator,
            .optimizations_count = 0,
        };
    }

    /// Optimize an AST node
    pub fn optimize(self: *Optimizer, node: *Node) OptimizeError!*Node {
        switch (node.*) {
            // Literals and variables cannot be optimized
            .int_literal, .float_literal, .variable => return node,

            // Optimize the value in assignments
            .assignment => |assign| {
                const opt_value = try self.optimize(assign.value);
                node.*.assignment.value = opt_value;
                return node;
            },

            // Constant fold unary operations
            .unary => |unary| {
                const opt_operand = try self.optimize(unary.operand);

                // Fold: -constant
                switch (opt_operand.*) {
                    .int_literal => |val| {
                        self.optimizations_count += 1;
                        const new_node = Node.create(self.allocator, .{
                            .int_literal = -val,
                        }) catch return OptimizeError.OutOfMemory;
                        return new_node;
                    },
                    .float_literal => |val| {
                        self.optimizations_count += 1;
                        const new_node = Node.create(self.allocator, .{
                            .float_literal = -val,
                        }) catch return OptimizeError.OutOfMemory;
                        return new_node;
                    },
                    else => {
                        node.*.unary.operand = opt_operand;
                        return node;
                    },
                }
            },

            // Constant fold binary operations
            .binary => |binary| {
                const opt_left = try self.optimize(binary.left);
                const opt_right = try self.optimize(binary.right);

                // Try to fold constant expressions
                if (try self.foldBinary(binary.op, opt_left, opt_right)) |folded| {
                    return folded;
                }

                // Can't fold - update children and return
                node.*.binary.left = opt_left;
                node.*.binary.right = opt_right;
                return node;
            },

            // Optimize each statement
            .statement_list => |list| {
                for (list.statements, 0..) |stmt, i| {
                    list.statements[i] = try self.optimize(stmt);
                }
                return node;
            },
        }
    }

    /// Try to fold a binary operation on two constant operands
    fn foldBinary(self: *Optimizer, op: BinaryOp, left: *Node, right: *Node) OptimizeError!?*Node {
        // Extract values if both are constants
        const left_int = if (left.* == .int_literal) left.int_literal else null;
        const right_int = if (right.* == .int_literal) right.int_literal else null;
        const left_float = if (left.* == .float_literal) left.float_literal else null;
        const right_float = if (right.* == .float_literal) right.float_literal else null;

        // Both integers - fold to integer
        if (left_int != null and right_int != null) {
            const l = left_int.?;
            const r = right_int.?;

            // Avoid division by zero at compile time
            if ((op == .div or op == .mod) and r == 0) {
                return null; // Don't fold, let runtime handle the error
            }

            const result: i64 = switch (op) {
                .add => l + r,
                .sub => l - r,
                .mul => l * r,
                .div => @divTrunc(l, r),
                .mod => @mod(l, r),
            };

            self.optimizations_count += 1;
            return Node.create(self.allocator, .{ .int_literal = result }) catch
                return OptimizeError.OutOfMemory;
        }

        // At least one float - fold to float
        if ((left_int != null or left_float != null) and
            (right_int != null or right_float != null))
        {
            // Only proceed if at least one is actually a float
            if (left_float != null or right_float != null) {
                const l: f64 = left_float orelse @floatFromInt(left_int.?);
                const r: f64 = right_float orelse @floatFromInt(right_int.?);

                // Avoid division by zero
                if ((op == .div or op == .mod) and r == 0) {
                    return null;
                }

                const result: f64 = switch (op) {
                    .add => l + r,
                    .sub => l - r,
                    .mul => l * r,
                    .div => l / r,
                    .mod => @mod(l, r),
                };

                self.optimizations_count += 1;
                return Node.create(self.allocator, .{ .float_literal = result }) catch
                    return OptimizeError.OutOfMemory;
            }
        }

        return null; // Cannot fold
    }

    /// Get the number of optimizations performed
    pub fn getOptimizationCount(self: *const Optimizer) usize {
        return self.optimizations_count;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "fold integer addition" {
    // Use arena for AST nodes - automatically freed when test ends
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 3 + 5 should fold to 8
    const left = try Node.create(allocator, .{ .int_literal = 3 });
    const right = try Node.create(allocator, .{ .int_literal = 5 });
    const binary = try Node.create(allocator, .{
        .binary = .{ .op = .add, .left = left, .right = right },
    });

    var optimizer = Optimizer.init(allocator);
    const result = try optimizer.optimize(binary);

    try std.testing.expectEqual(Node{ .int_literal = 8 }, result.*);
    try std.testing.expectEqual(@as(usize, 1), optimizer.getOptimizationCount());
}

test "fold chained operations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 3 + 5 * 2 should fold to 13
    const three = try Node.create(allocator, .{ .int_literal = 3 });
    const five = try Node.create(allocator, .{ .int_literal = 5 });
    const two = try Node.create(allocator, .{ .int_literal = 2 });

    const mul = try Node.create(allocator, .{
        .binary = .{ .op = .mul, .left = five, .right = two },
    });

    const add = try Node.create(allocator, .{
        .binary = .{ .op = .add, .left = three, .right = mul },
    });

    var optimizer = Optimizer.init(allocator);
    const result = try optimizer.optimize(add);

    try std.testing.expectEqual(Node{ .int_literal = 13 }, result.*);
}

test "fold negation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // -5 should fold to -5 (literal)
    const five = try Node.create(allocator, .{ .int_literal = 5 });
    const neg = try Node.create(allocator, .{
        .unary = .{ .op = .neg, .operand = five },
    });

    var optimizer = Optimizer.init(allocator);
    const result = try optimizer.optimize(neg);

    try std.testing.expectEqual(Node{ .int_literal = -5 }, result.*);
}
