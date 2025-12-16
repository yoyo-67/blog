//! Virtual Machine for the mini math compiler
//!
//! Executes bytecode using a stack-based architecture.

const std = @import("std");
const codegen_mod = @import("codegen.zig");

pub const ByteCode = codegen_mod.ByteCode;
pub const CompiledCode = codegen_mod.CompiledCode;

/// Runtime value - can be integer or float
pub const Value = union(enum) {
    int: i64,
    float: f64,

    /// Convert to float regardless of actual type
    pub fn asFloat(self: Value) f64 {
        return switch (self) {
            .int => |i| @floatFromInt(i),
            .float => |f| f,
        };
    }

    /// Check if this is a float value
    pub fn isFloat(self: Value) bool {
        return self == .float;
    }

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
        }
    }
};

pub const VmError = error{
    StackUnderflow,
    StackOverflow,
    InvalidOpcode,
    DivisionByZero,
    UndefinedVariable,
};

/// Virtual Machine - interprets bytecode
pub const VM = struct {
    /// Bytecode to execute
    code: []const u8,
    /// Integer constant pool
    constants_int: []const i64,
    /// Float constant pool
    constants_float: []const f64,
    /// Operand stack
    stack: [256]Value,
    /// Stack pointer (points to next free slot)
    stack_top: usize,
    /// Variable storage
    variables: [256]?Value,
    /// Instruction pointer
    ip: usize,
    /// Enable debug tracing
    trace: bool,

    pub fn init(compiled: CompiledCode) VM {
        return .{
            .code = compiled.code,
            .constants_int = compiled.constants_int,
            .constants_float = compiled.constants_float,
            .stack = undefined,
            .stack_top = 0,
            .variables = [_]?Value{null} ** 256,
            .ip = 0,
            .trace = false,
        };
    }

    /// Enable execution tracing
    pub fn enableTrace(self: *VM) void {
        self.trace = true;
    }

    /// Push a value onto the stack
    fn push(self: *VM, value: Value) VmError!void {
        if (self.stack_top >= 256) return VmError.StackOverflow;
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    /// Pop a value from the stack
    fn pop(self: *VM) VmError!Value {
        if (self.stack_top == 0) return VmError.StackUnderflow;
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    /// Read the next byte from the bytecode
    fn readByte(self: *VM) u8 {
        const byte = self.code[self.ip];
        self.ip += 1;
        return byte;
    }

    /// Execute the bytecode and return the result
    pub fn run(self: *VM) VmError!Value {
        while (true) {
            const opcode = self.readByte();

            if (self.trace) {
                std.debug.print("  IP={d:3} OP={s} STACK=[", .{
                    self.ip - 1,
                    @tagName(@as(ByteCode, @enumFromInt(opcode))),
                });
                for (self.stack[0..self.stack_top], 0..) |v, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{any}", .{v});
                }
                std.debug.print("]\n", .{});
            }

            switch (@as(ByteCode, @enumFromInt(opcode))) {
                .push_int => {
                    const idx = self.readByte();
                    try self.push(.{ .int = self.constants_int[idx] });
                },

                .push_float => {
                    const idx = self.readByte();
                    try self.push(.{ .float = self.constants_float[idx] });
                },

                .add, .sub, .mul, .div, .mod => {
                    const b = try self.pop();
                    const a = try self.pop();

                    // If either is float, do float arithmetic
                    if (a.isFloat() or b.isFloat()) {
                        const af = a.asFloat();
                        const bf = b.asFloat();
                        const result: f64 = switch (@as(ByteCode, @enumFromInt(opcode))) {
                            .add => af + bf,
                            .sub => af - bf,
                            .mul => af * bf,
                            .div => if (bf == 0) return VmError.DivisionByZero else af / bf,
                            .mod => @mod(af, bf),
                            else => unreachable,
                        };
                        try self.push(.{ .float = result });
                    } else {
                        const ai = a.int;
                        const bi = b.int;
                        const result: i64 = switch (@as(ByteCode, @enumFromInt(opcode))) {
                            .add => ai + bi,
                            .sub => ai - bi,
                            .mul => ai * bi,
                            .div => if (bi == 0) return VmError.DivisionByZero else @divTrunc(ai, bi),
                            .mod => @mod(ai, bi),
                            else => unreachable,
                        };
                        try self.push(.{ .int = result });
                    }
                },

                .neg => {
                    const a = try self.pop();
                    switch (a) {
                        .int => |i| try self.push(.{ .int = -i }),
                        .float => |f| try self.push(.{ .float = -f }),
                    }
                },

                .load => {
                    const idx = self.readByte();
                    if (self.variables[idx]) |value| {
                        try self.push(value);
                    } else {
                        return VmError.UndefinedVariable;
                    }
                },

                .store => {
                    const idx = self.readByte();
                    const value = try self.pop();
                    self.variables[idx] = value;
                    try self.push(value); // Assignment returns the value
                },

                .halt => {
                    if (self.stack_top > 0) {
                        return self.stack[self.stack_top - 1];
                    }
                    return .{ .int = 0 };
                },
            }
        }
    }

    /// Get current stack contents (for debugging)
    pub fn getStack(self: *const VM) []const Value {
        return self.stack[0..self.stack_top];
    }
};

// ============================================================================
// Tests
// ============================================================================

test "vm simple addition" {
    // Bytecode for: 3 + 5
    const code = [_]u8{
        0x01, 0x00, // PUSH_INT [0] (3)
        0x01, 0x01, // PUSH_INT [1] (5)
        0x10, // ADD
        0xFF, // HALT
    };
    const constants_int = [_]i64{ 3, 5 };
    const constants_float = [_]f64{};

    const compiled = CompiledCode{
        .code = &code,
        .constants_int = &constants_int,
        .constants_float = &constants_float,
        .var_count = 0,
    };

    var vm = VM.init(compiled);
    const result = try vm.run();

    try std.testing.expectEqual(Value{ .int = 8 }, result);
}

test "vm float multiplication" {
    // Bytecode for: 2.5 * 4
    const code = [_]u8{
        0x02, 0x00, // PUSH_FLOAT [0] (2.5)
        0x01, 0x00, // PUSH_INT [0] (4)
        0x12, // MUL
        0xFF, // HALT
    };
    const constants_int = [_]i64{4};
    const constants_float = [_]f64{2.5};

    const compiled = CompiledCode{
        .code = &code,
        .constants_int = &constants_int,
        .constants_float = &constants_float,
        .var_count = 0,
    };

    var vm = VM.init(compiled);
    const result = try vm.run();

    try std.testing.expectEqual(@as(f64, 10.0), result.float);
}

test "vm variable storage" {
    // Bytecode for: x = 42
    const code = [_]u8{
        0x01, 0x00, // PUSH_INT [0] (42)
        0x21, 0x00, // STORE var[0]
        0xFF, // HALT
    };
    const constants_int = [_]i64{42};
    const constants_float = [_]f64{};

    const compiled = CompiledCode{
        .code = &code,
        .constants_int = &constants_int,
        .constants_float = &constants_float,
        .var_count = 1,
    };

    var vm = VM.init(compiled);
    const result = try vm.run();

    try std.testing.expectEqual(Value{ .int = 42 }, result);
    try std.testing.expectEqual(Value{ .int = 42 }, vm.variables[0].?);
}

test "vm division by zero" {
    const code = [_]u8{
        0x01, 0x00, // PUSH_INT [0] (5)
        0x01, 0x01, // PUSH_INT [1] (0)
        0x13, // DIV
        0xFF, // HALT
    };
    const constants_int = [_]i64{ 5, 0 };
    const constants_float = [_]f64{};

    const compiled = CompiledCode{
        .code = &code,
        .constants_int = &constants_int,
        .constants_float = &constants_float,
        .var_count = 0,
    };

    var vm = VM.init(compiled);
    const result = vm.run();

    try std.testing.expectError(VmError.DivisionByZero, result);
}
