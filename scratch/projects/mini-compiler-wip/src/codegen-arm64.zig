const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const zir_mod = @import("zir.zig");
const ast_mod = @import("ast.zig");
const Type = @import("types.zig").Type;
const Value = @import("types.zig").Value;

const Gen = @This();

output: std.ArrayListUnmanaged(u8),
allocator: Allocator,

pub fn init(allocator: Allocator) Gen {
    return .{
        .output = .empty,
        .allocator = allocator,
    };
}

pub fn generate(self: *Gen, program: zir_mod.Program) ![]const u8 {
    const functions = program.functions();
    for (functions) |function| {
        try self.generateFunction(function);
        try self.emit("\n");
    }
    return self.output.toOwnedSlice(self.allocator);
}

pub fn generateSingleFunction(self: *Gen, function: zir_mod.Function) ![]const u8 {
    try self.generateFunction(function);
    return self.output.toOwnedSlice(self.allocator);
}

fn generateFunction(self: *Gen, function: zir_mod.Function) !void {
    // Emit .global directive with _ prefix for macOS
    try self.emit(".global _");
    try self.emit(function.name);
    try self.emit("\n");

    // Emit label
    try self.emit("_");
    try self.emit(function.name);
    try self.emit(":\n");

    // Function prologue: save frame pointer and link register
    try self.emit("    stp x29, x30, [sp, #-16]!\n");
    try self.emit("    mov x29, sp\n");

    // Track value info for each instruction
    var value_info = std.AutoHashMap(u32, ValueInfo).init(self.allocator);
    defer value_info.deinit();

    // Generate instructions
    for (function.instructions(), 0..) |inst, idx| {
        try self.generateInstruction(inst, @intCast(idx), &value_info, function);
    }

    // Function epilogue is emitted by return_stmt
}

const ValueInfo = union(enum) {
    constant: i64,
    register: u8, // w8-w15 for temps, w0-w7 for params
    parameter: u8, // Parameter index (0-7)
};

fn generateInstruction(
    self: *Gen,
    inst: zir_mod.Instruction,
    idx: u32,
    value_info: *std.AutoHashMap(u32, ValueInfo),
    function: zir_mod.Function,
) !void {
    switch (inst) {
        .literal => |lit| {
            // Track constant value - will be inlined when used
            const val: i64 = switch (lit.value) {
                .int => |v| v,
                .float => |v| @intFromFloat(v),
                .boolean => |v| if (v) 1 else 0,
            };
            try value_info.put(idx, .{ .constant = val });
        },
        .param_ref => |ref| {
            // Parameters are in w0-w7
            try value_info.put(idx, .{ .parameter = @intCast(ref.value) });
        },
        .decl => |decl| {
            // Variable declaration - copy the source value info
            const source_info = value_info.get(decl.value) orelse unreachable;
            try value_info.put(idx, source_info);
        },
        .decl_ref => |ref| {
            // Variable reference - look up in previous instructions
            const var_idx = self.findVariableDecl(function, ref.name, idx);
            if (var_idx) |vi| {
                const source_info = value_info.get(vi) orelse unreachable;
                try value_info.put(idx, source_info);
            }
        },
        .add => |op| {
            const dest_reg: u8 = 8 + @as(u8, @intCast(idx % 8));
            // add supports: add Rd, Rn, #imm OR add Rd, Rn, Rm
            // LHS must be register, RHS can be immediate or register
            const lhs_reg = try self.ensureRegister(op.lhs, value_info, 16); // w16 as temp
            try self.emit("    add w");
            try self.emitInt(dest_reg);
            try self.emit(", w");
            try self.emitInt(lhs_reg);
            try self.emit(", ");
            try self.emitOperand(op.rhs, value_info);
            try self.emit("\n");
            try value_info.put(idx, .{ .register = dest_reg });
        },
        .sub => |op| {
            const dest_reg: u8 = 8 + @as(u8, @intCast(idx % 8));
            // sub supports: sub Rd, Rn, #imm OR sub Rd, Rn, Rm
            const lhs_reg = try self.ensureRegister(op.lhs, value_info, 16);
            try self.emit("    sub w");
            try self.emitInt(dest_reg);
            try self.emit(", w");
            try self.emitInt(lhs_reg);
            try self.emit(", ");
            try self.emitOperand(op.rhs, value_info);
            try self.emit("\n");
            try value_info.put(idx, .{ .register = dest_reg });
        },
        .mul => |op| {
            const dest_reg: u8 = 8 + @as(u8, @intCast(idx % 8));
            // mul requires all register operands: mul Rd, Rn, Rm
            const lhs_reg = try self.ensureRegister(op.lhs, value_info, 16);
            const rhs_reg = try self.ensureRegister(op.rhs, value_info, 17);
            try self.emit("    mul w");
            try self.emitInt(dest_reg);
            try self.emit(", w");
            try self.emitInt(lhs_reg);
            try self.emit(", w");
            try self.emitInt(rhs_reg);
            try self.emit("\n");
            try value_info.put(idx, .{ .register = dest_reg });
        },
        .div => |op| {
            const dest_reg: u8 = 8 + @as(u8, @intCast(idx % 8));
            // sdiv requires all register operands: sdiv Rd, Rn, Rm
            const lhs_reg = try self.ensureRegister(op.lhs, value_info, 16);
            const rhs_reg = try self.ensureRegister(op.rhs, value_info, 17);
            try self.emit("    sdiv w");
            try self.emitInt(dest_reg);
            try self.emit(", w");
            try self.emitInt(lhs_reg);
            try self.emit(", w");
            try self.emitInt(rhs_reg);
            try self.emit("\n");
            try value_info.put(idx, .{ .register = dest_reg });
        },
        .return_stmt => |ret| {
            const info = value_info.get(ret.value) orelse unreachable;
            switch (info) {
                .constant => |val| {
                    try self.emit("    mov w0, #");
                    try self.emitInt(@intCast(val));
                    try self.emit("\n");
                },
                .register => |reg| {
                    if (reg != 0) {
                        try self.emit("    mov w0, w");
                        try self.emitInt(reg);
                        try self.emit("\n");
                    }
                },
                .parameter => |param| {
                    if (param != 0) {
                        try self.emit("    mov w0, w");
                        try self.emitInt(param);
                        try self.emit("\n");
                    }
                },
            }
            // Epilogue
            try self.emit("    ldp x29, x30, [sp], #16\n");
            try self.emit("    ret\n");
        },
        .call => |call| {
            // Move arguments to w0-w7
            for (call.args, 0..) |arg, i| {
                const arg_info = value_info.get(arg) orelse unreachable;
                switch (arg_info) {
                    .constant => |val| {
                        try self.emit("    mov w");
                        try self.emitInt(i);
                        try self.emit(", #");
                        try self.emitInt(@intCast(val));
                        try self.emit("\n");
                    },
                    .register => |reg| {
                        if (reg != @as(u8, @intCast(i))) {
                            try self.emit("    mov w");
                            try self.emitInt(i);
                            try self.emit(", w");
                            try self.emitInt(reg);
                            try self.emit("\n");
                        }
                    },
                    .parameter => |param| {
                        if (param != @as(u8, @intCast(i))) {
                            try self.emit("    mov w");
                            try self.emitInt(i);
                            try self.emit(", w");
                            try self.emitInt(param);
                            try self.emit("\n");
                        }
                    },
                }
            }
            // Call function with _ prefix
            try self.emit("    bl _");
            try self.emit(call.name);
            try self.emit("\n");
            // Result is in w0, but we track it as a register for later use
            const dest_reg: u8 = 8 + @as(u8, @intCast(idx % 8));
            try self.emit("    mov w");
            try self.emitInt(dest_reg);
            try self.emit(", w0\n");
            try value_info.put(idx, .{ .register = dest_reg });
        },
    }
}

fn findVariableDecl(self: *Gen, function: zir_mod.Function, name: []const u8, before_idx: u32) ?u32 {
    _ = self;
    var i: u32 = before_idx;
    while (i > 0) {
        i -= 1;
        const inst = function.instructionAt(i);
        if (inst.* == .decl) {
            if (mem.eql(u8, inst.decl.name, name)) {
                return inst.decl.value;
            }
        }
    }
    return null;
}

/// Ensure a value is in a register, loading from immediate if needed
/// Returns the register number containing the value
fn ensureRegister(self: *Gen, ref: u32, value_info: *std.AutoHashMap(u32, ValueInfo), temp_reg: u8) !u8 {
    const info = value_info.get(ref) orelse unreachable;
    switch (info) {
        .constant => |val| {
            // Load immediate into temp register
            try self.emit("    mov w");
            try self.emitInt(temp_reg);
            try self.emit(", #");
            try self.emitInt(@intCast(val));
            try self.emit("\n");
            return temp_reg;
        },
        .register => |reg| return reg,
        .parameter => |param| return param,
    }
}

fn emitOperand(self: *Gen, ref: u32, value_info: *std.AutoHashMap(u32, ValueInfo)) !void {
    const info = value_info.get(ref) orelse unreachable;
    switch (info) {
        .constant => |val| {
            try self.emit("#");
            try self.emitInt(@intCast(val));
        },
        .register => |reg| {
            try self.emit("w");
            try self.emitInt(reg);
        },
        .parameter => |param| {
            try self.emit("w");
            try self.emitInt(param);
        },
    }
}

fn emit(self: *Gen, str: []const u8) !void {
    try self.output.appendSlice(self.allocator, str);
}

fn emitInt(self: *Gen, val: usize) !void {
    try std.fmt.format(self.output.writer(self.allocator), "{d}", .{val});
}

// ============================================================================
// Tests
// ============================================================================

fn testGenerate(input: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);

    var gen = Gen.init(allocator);
    const result = try gen.generate(program);

    // Copy result to testing allocator since arena will be freed
    const copy = try testing.allocator.alloc(u8, result.len);
    @memcpy(copy, result);
    return copy;
}

test "simple return constant" {
    const result = try testGenerate("fn main() i32 { return 42; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _main
        \\_main:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w0, #42
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "return with arithmetic" {
    const result = try testGenerate("fn calc() i32 { return 1 + 2; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _calc
        \\_calc:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w16, #1
        \\    add w10, w16, #2
        \\    mov w0, w10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function with parameter" {
    const result = try testGenerate("fn square(x: i32) i32 { return x * x; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _square
        \\_square:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mul w10, w0, w0
        \\    mov w0, w10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function with two parameters" {
    const result = try testGenerate("fn add(a: i32, b: i32) i32 { return a + b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _add
        \\_add:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    add w10, w0, w1
        \\    mov w0, w10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "subtraction" {
    const result = try testGenerate("fn sub(a: i32, b: i32) i32 { return a - b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _sub
        \\_sub:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    sub w10, w0, w1
        \\    mov w0, w10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "division" {
    const result = try testGenerate("fn div(a: i32, b: i32) i32 { return a / b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _div
        \\_div:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    sdiv w10, w0, w1
        \\    mov w0, w10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "variable declaration and use" {
    const result = try testGenerate(
        \\fn foo() i32 {
        \\  const x = 10;
        \\  return x;
        \\}
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _foo
        \\_foo:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w0, #10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function call no args" {
    const result = try testGenerate(
        \\fn foo() i32 { return 42; }
        \\fn main() i32 { return foo(); }
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _foo
        \\_foo:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w0, #42
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\.global _main
        \\_main:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    bl _foo
        \\    mov w8, w0
        \\    mov w0, w8
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}

test "function call with args" {
    const result = try testGenerate(
        \\fn add(a: i32, b: i32) i32 { return a + b; }
        \\fn main() i32 { return add(3, 5); }
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\.global _add
        \\_add:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    add w10, w0, w1
        \\    mov w0, w10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\.global _main
        \\_main:
        \\    stp x29, x30, [sp, #-16]!
        \\    mov x29, sp
        \\    mov w0, #3
        \\    mov w1, #5
        \\    bl _add
        \\    mov w10, w0
        \\    mov w0, w10
        \\    ldp x29, x30, [sp], #16
        \\    ret
        \\
        \\
    , result);
}
