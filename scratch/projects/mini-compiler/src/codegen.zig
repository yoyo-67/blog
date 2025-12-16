//! Code Generator for the mini math compiler
//!
//! Converts IR instructions into bytecode for the virtual machine.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("ir.zig");

pub const Instruction = ir_mod.Instruction;
pub const OpCode = ir_mod.OpCode;

/// Bytecode operation codes (single byte each)
pub const ByteCode = enum(u8) {
    push_int = 0x01,
    push_float = 0x02,
    add = 0x10,
    sub = 0x11,
    mul = 0x12,
    div = 0x13,
    mod = 0x14,
    neg = 0x15,
    load = 0x20,
    store = 0x21,
    halt = 0xFF,

    pub fn format(
        self: ByteCode,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}(0x{X:0>2})", .{ @tagName(self), @intFromEnum(self) });
    }
};

/// Compiled bytecode with constant pools
pub const CompiledCode = struct {
    /// The bytecode instructions
    code: []const u8,
    /// Integer constant pool
    constants_int: []const i64,
    /// Float constant pool
    constants_float: []const f64,
    /// Variable name to index mapping
    var_count: u8,

    pub fn deinit(self: *CompiledCode, allocator: Allocator) void {
        allocator.free(self.code);
        allocator.free(self.constants_int);
        allocator.free(self.constants_float);
    }

    /// Print bytecode for debugging
    pub fn dump(self: *const CompiledCode, writer: anytype) !void {
        try writer.writeAll("Bytecode:\n");

        var i: usize = 0;
        while (i < self.code.len) {
            const op: ByteCode = @enumFromInt(self.code[i]);
            try writer.print("  {d:3}: {any}", .{ i, op });

            switch (op) {
                .push_int => {
                    const idx = self.code[i + 1];
                    try writer.print(" [{d}] = {d}", .{ idx, self.constants_int[idx] });
                    i += 2;
                },
                .push_float => {
                    const idx = self.code[i + 1];
                    try writer.print(" [{d}] = {d}", .{ idx, self.constants_float[idx] });
                    i += 2;
                },
                .load, .store => {
                    const idx = self.code[i + 1];
                    try writer.print(" var[{d}]", .{idx});
                    i += 2;
                },
                else => i += 1,
            }
            try writer.writeAll("\n");
        }

        try writer.print("\nConstants (int): {any}\n", .{self.constants_int});
        try writer.print("Constants (float): {any}\n", .{self.constants_float});
    }
};

/// Code Generator - converts IR to bytecode
pub const Generator = struct {
    code: std.ArrayList(u8),
    constants_int: std.ArrayList(i64),
    constants_float: std.ArrayList(f64),
    var_indices: std.StringHashMap(u8),
    next_var_index: u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Generator {
        return .{
            .code = .empty,
            .constants_int = .empty,
            .constants_float = .empty,
            .var_indices = std.StringHashMap(u8).init(allocator),
            .next_var_index = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Generator) void {
        self.code.deinit(self.allocator);
        self.constants_int.deinit(self.allocator);
        self.constants_float.deinit(self.allocator);
        self.var_indices.deinit();
    }

    /// Emit a single byte
    fn emitByte(self: *Generator, byte: u8) !void {
        try self.code.append(self.allocator, byte);
    }

    /// Get or create variable index
    fn getOrCreateVarIndex(self: *Generator, name: []const u8) !u8 {
        if (self.var_indices.get(name)) |idx| {
            return idx;
        }
        const idx = self.next_var_index;
        self.next_var_index += 1;
        try self.var_indices.put(name, idx);
        return idx;
    }

    /// Generate bytecode from IR instructions
    pub fn generate(self: *Generator, ir: []const Instruction) !void {
        for (ir) |inst| {
            switch (inst.op) {
                .push_int => {
                    try self.emitByte(@intFromEnum(ByteCode.push_int));
                    const idx: u8 = @intCast(self.constants_int.items.len);
                    try self.constants_int.append(self.allocator, inst.operand.int_value);
                    try self.emitByte(idx);
                },
                .push_float => {
                    try self.emitByte(@intFromEnum(ByteCode.push_float));
                    const idx: u8 = @intCast(self.constants_float.items.len);
                    try self.constants_float.append(self.allocator, inst.operand.float_value);
                    try self.emitByte(idx);
                },
                .add => try self.emitByte(@intFromEnum(ByteCode.add)),
                .sub => try self.emitByte(@intFromEnum(ByteCode.sub)),
                .mul => try self.emitByte(@intFromEnum(ByteCode.mul)),
                .div => try self.emitByte(@intFromEnum(ByteCode.div)),
                .mod => try self.emitByte(@intFromEnum(ByteCode.mod)),
                .neg => try self.emitByte(@intFromEnum(ByteCode.neg)),
                .load => {
                    try self.emitByte(@intFromEnum(ByteCode.load));
                    const idx = try self.getOrCreateVarIndex(inst.operand.var_name);
                    try self.emitByte(idx);
                },
                .store => {
                    try self.emitByte(@intFromEnum(ByteCode.store));
                    const idx = try self.getOrCreateVarIndex(inst.operand.var_name);
                    try self.emitByte(idx);
                },
                .int_to_float => {}, // Not used in bytecode
            }
        }
        try self.emitByte(@intFromEnum(ByteCode.halt));
    }

    /// Finalize and return the compiled code
    /// Transfers ownership of bytecode and constants, cleans up internal state
    /// After finalize(), deinit() can still be safely called (it becomes a no-op)
    pub fn finalize(self: *Generator) !CompiledCode {
        // Clean up var_indices since we're done with it (not needed in output)
        self.var_indices.deinit();
        // Re-initialize to empty so deinit() is safe to call after finalize()
        self.var_indices = std.StringHashMap(u8).init(self.allocator);

        return .{
            .code = try self.code.toOwnedSlice(self.allocator),
            .constants_int = try self.constants_int.toOwnedSlice(self.allocator),
            .constants_float = try self.constants_float.toOwnedSlice(self.allocator),
            .var_count = self.next_var_index,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "generate bytecode for push and add" {
    const allocator = std.testing.allocator;

    const ir = [_]Instruction{
        .{ .op = .push_int, .operand = .{ .int_value = 3 } },
        .{ .op = .push_int, .operand = .{ .int_value = 5 } },
        .{ .op = .add, .operand = .{ .none = {} } },
    };

    var gen = Generator.init(allocator);
    defer gen.deinit();

    try gen.generate(&ir);
    var compiled = try gen.finalize();
    defer compiled.deinit(allocator);

    // Expected: PUSH_INT 0, PUSH_INT 1, ADD, HALT
    try std.testing.expectEqual(@as(usize, 6), compiled.code.len);
    try std.testing.expectEqual(@as(u8, 0x01), compiled.code[0]); // push_int
    try std.testing.expectEqual(@as(u8, 0x00), compiled.code[1]); // index 0
    try std.testing.expectEqual(@as(u8, 0x01), compiled.code[2]); // push_int
    try std.testing.expectEqual(@as(u8, 0x01), compiled.code[3]); // index 1
    try std.testing.expectEqual(@as(u8, 0x10), compiled.code[4]); // add
    try std.testing.expectEqual(@as(u8, 0xFF), compiled.code[5]); // halt

    try std.testing.expectEqual(@as(i64, 3), compiled.constants_int[0]);
    try std.testing.expectEqual(@as(i64, 5), compiled.constants_int[1]);
}
