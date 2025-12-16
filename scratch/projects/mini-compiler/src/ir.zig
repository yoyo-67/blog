//! Intermediate Representation (IR) for the mini math compiler
//!
//! The IR is a linear sequence of stack-based instructions,
//! easier to work with than a tree for code generation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");

pub const Node = ast_mod.Node;
pub const BinaryOp = ast_mod.BinaryOp;
pub const UnaryOp = ast_mod.UnaryOp;

/// IR operation codes
pub const OpCode = enum {
    /// Push an integer constant onto the stack
    push_int,
    /// Push a float constant onto the stack
    push_float,
    /// Pop two values, push their sum
    add,
    /// Pop two values, push their difference (a - b)
    sub,
    /// Pop two values, push their product
    mul,
    /// Pop two values, push their quotient (a / b)
    div,
    /// Pop two values, push the remainder (a % b)
    mod,
    /// Pop one value, push its negation
    neg,
    /// Push the value of a variable onto the stack
    load,
    /// Pop a value and store it in a variable
    store,
    /// Convert top of stack from int to float
    int_to_float,

    pub fn format(
        self: OpCode,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(@tagName(self));
    }
};

/// An IR instruction
pub const Instruction = struct {
    op: OpCode,
    operand: Operand,

    pub const Operand = union {
        int_value: i64,
        float_value: f64,
        var_name: []const u8,
        none: void,
    };

    pub fn format(
        self: Instruction,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}", .{@tagName(self.op)});
        switch (self.op) {
            .push_int => try writer.print(" {d}", .{self.operand.int_value}),
            .push_float => try writer.print(" {d}", .{self.operand.float_value}),
            .load, .store => try writer.print(" {s}", .{self.operand.var_name}),
            else => {},
        }
    }
};

/// IR Generator - converts AST to IR instructions
pub const Generator = struct {
    instructions: std.ArrayList(Instruction),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Generator {
        return .{
            .instructions = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Generator) void {
        self.instructions.deinit(self.allocator);
    }

    /// Emit an instruction
    fn emit(self: *Generator, inst: Instruction) !void {
        try self.instructions.append(self.allocator, inst);
    }

    /// Generate IR for an AST node
    pub fn generate(self: *Generator, node: *Node) !void {
        switch (node.*) {
            .int_literal => |value| {
                try self.emit(.{
                    .op = .push_int,
                    .operand = .{ .int_value = value },
                });
            },

            .float_literal => |value| {
                try self.emit(.{
                    .op = .push_float,
                    .operand = .{ .float_value = value },
                });
            },

            .variable => |name| {
                try self.emit(.{
                    .op = .load,
                    .operand = .{ .var_name = name },
                });
            },

            .assignment => |assign| {
                try self.generate(assign.value);
                try self.emit(.{
                    .op = .store,
                    .operand = .{ .var_name = assign.name },
                });
            },

            .unary => |unary| {
                try self.generate(unary.operand);
                switch (unary.op) {
                    .neg => try self.emit(.{
                        .op = .neg,
                        .operand = .{ .none = {} },
                    }),
                }
            },

            .binary => |binary| {
                try self.generate(binary.left);
                try self.generate(binary.right);
                const op: OpCode = switch (binary.op) {
                    .add => .add,
                    .sub => .sub,
                    .mul => .mul,
                    .div => .div,
                    .mod => .mod,
                };
                try self.emit(.{ .op = op, .operand = .{ .none = {} } });
            },

            .statement_list => |list| {
                for (list.statements) |stmt| {
                    try self.generate(stmt);
                }
            },
        }
    }

    /// Get the generated instructions
    pub fn getInstructions(self: *const Generator) []const Instruction {
        return self.instructions.items;
    }

    /// Print the IR for debugging
    pub fn dump(self: *const Generator, writer: anytype) !void {
        try writer.writeAll("IR Instructions:\n");
        for (self.instructions.items, 0..) |inst, i| {
            try writer.print("  {d:3}: {any}\n", .{ i, inst });
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "generate simple addition" {
    const allocator = std.testing.allocator;

    // 3 + 5
    const left = try Node.create(allocator, .{ .int_literal = 3 });
    defer allocator.destroy(left);
    const right = try Node.create(allocator, .{ .int_literal = 5 });
    defer allocator.destroy(right);
    const binary = try Node.create(allocator, .{
        .binary = .{ .op = .add, .left = left, .right = right },
    });
    defer allocator.destroy(binary);

    var gen = Generator.init(allocator);
    defer gen.deinit();

    try gen.generate(binary);

    const insts = gen.getInstructions();
    try std.testing.expectEqual(@as(usize, 3), insts.len);
    try std.testing.expectEqual(OpCode.push_int, insts[0].op);
    try std.testing.expectEqual(@as(i64, 3), insts[0].operand.int_value);
    try std.testing.expectEqual(OpCode.push_int, insts[1].op);
    try std.testing.expectEqual(@as(i64, 5), insts[1].operand.int_value);
    try std.testing.expectEqual(OpCode.add, insts[2].op);
}

test "generate variable assignment" {
    const allocator = std.testing.allocator;

    // x = 42
    const value = try Node.create(allocator, .{ .int_literal = 42 });
    defer allocator.destroy(value);
    const assign = try Node.create(allocator, .{
        .assignment = .{ .name = "x", .value = value },
    });
    defer allocator.destroy(assign);

    var gen = Generator.init(allocator);
    defer gen.deinit();

    try gen.generate(assign);

    const insts = gen.getInstructions();
    try std.testing.expectEqual(@as(usize, 2), insts.len);
    try std.testing.expectEqual(OpCode.push_int, insts[0].op);
    try std.testing.expectEqual(OpCode.store, insts[1].op);
    try std.testing.expectEqualStrings("x", insts[1].operand.var_name);
}
