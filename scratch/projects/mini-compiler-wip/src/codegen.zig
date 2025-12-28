const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const zir_mod = @import("zir.zig");
const sema_mod = @import("sema.zig");
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
    for (functions, 0..) |function, i| {
        try self.generateFunction(function);
        if (i < functions.len - 1) {
            try self.emit("\n");
        }
    }
    return self.output.toOwnedSlice(self.allocator);
}

/// Generate LLVM IR for a single function (used by per-function caching)
pub fn generateSingleFunction(self: *Gen, function: zir_mod.Function) ![]const u8 {
    try self.generateFunction(function);
    return self.output.toOwnedSlice(self.allocator);
}

fn generateFunction(self: *Gen, function: zir_mod.Function) !void {
    // Emit function signature: define <return_type> @<name>(<params>) {
    try self.emit("define ");
    try self.emitType(function.return_type orelse .void);
    try self.emit(" @");
    try self.emit(function.name);
    try self.emit("(");

    // Emit parameters
    for (function.params, 0..) |param, i| {
        if (i > 0) try self.emit(", ");
        try self.emitType(param.type);
        try self.emit(" %p");
        try self.emitInt(i);
    }

    try self.emit(") {\n");
    try self.emit("entry:\n");

    // Track value info for each instruction
    var value_info = std.AutoHashMap(u32, ValueInfo).init(self.allocator);
    defer value_info.deinit();

    // Generate instructions
    for (function.instructions(), 0..) |inst, idx| {
        try self.generateInstruction(inst, @intCast(idx), &value_info, function);
    }

    try self.emit("}\n");
}

const ValueInfo = union(enum) {
    constant: Value,
    instruction: u32,
    parameter: u32,
    variable: u32, // Points to the instruction that computes the value
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
            // Constants are inlined, just track them
            try value_info.put(idx, .{ .constant = lit.value });
        },
        .param_ref => |ref| {
            // Parameters are referenced as %pN
            try value_info.put(idx, .{ .parameter = ref.value });
        },
        .decl => |decl| {
            // Variable declaration - track what instruction computes its value
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
            try self.emit("    %");
            try self.emitInt(idx);
            try self.emit(" = add i32 ");
            try self.emitOperand(op.lhs, value_info);
            try self.emit(", ");
            try self.emitOperand(op.rhs, value_info);
            try self.emit("\n");
            try value_info.put(idx, .{ .instruction = idx });
        },
        .sub => |op| {
            try self.emit("    %");
            try self.emitInt(idx);
            try self.emit(" = sub i32 ");
            try self.emitOperand(op.lhs, value_info);
            try self.emit(", ");
            try self.emitOperand(op.rhs, value_info);
            try self.emit("\n");
            try value_info.put(idx, .{ .instruction = idx });
        },
        .mul => |op| {
            try self.emit("    %");
            try self.emitInt(idx);
            try self.emit(" = mul i32 ");
            try self.emitOperand(op.lhs, value_info);
            try self.emit(", ");
            try self.emitOperand(op.rhs, value_info);
            try self.emit("\n");
            try value_info.put(idx, .{ .instruction = idx });
        },
        .div => |op| {
            try self.emit("    %");
            try self.emitInt(idx);
            try self.emit(" = sdiv i32 ");
            try self.emitOperand(op.lhs, value_info);
            try self.emit(", ");
            try self.emitOperand(op.rhs, value_info);
            try self.emit("\n");
            try value_info.put(idx, .{ .instruction = idx });
        },
        .return_stmt => |ret| {
            try self.emit("    ret i32 ");
            try self.emitOperand(ret.value, value_info);
            try self.emit("\n");
        },
        .call => |call| {
            try self.emit("    %");
            try self.emitInt(idx);
            try self.emit(" = call i32 @");
            try self.emit(call.name);
            try self.emit("(");
            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try self.emit("i32 ");
                try self.emitOperand(arg, value_info);
            }
            try self.emit(")\n");
            try value_info.put(idx, .{ .instruction = idx });
        },
    }
}

fn findVariableDecl(self: *Gen, function: zir_mod.Function, name: []const u8, before_idx: u32) ?u32 {
    _ = self;
    // Search backwards through instructions to find the declaration
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

fn emitOperand(self: *Gen, ref: u32, value_info: *std.AutoHashMap(u32, ValueInfo)) !void {
    const info = value_info.get(ref) orelse unreachable;
    switch (info) {
        .constant => |val| {
            switch (val) {
                .int => |v| try self.emitInt(@intCast(v)),
                .float => |v| try std.fmt.format(self.output.writer(self.allocator), "{d}", .{v}),
                .boolean => |v| try self.emitInt(if (v) 1 else 0),
            }
        },
        .instruction => |inst_idx| {
            try self.emit("%");
            try self.emitInt(inst_idx);
        },
        .parameter => |param_idx| {
            try self.emit("%p");
            try self.emitInt(param_idx);
        },
        .variable => |inst_idx| {
            try self.emit("%");
            try self.emitInt(inst_idx);
        },
    }
}

fn emitType(self: *Gen, t: Type) !void {
    const type_str = switch (t) {
        .i32 => "i32",
        .f64 => "double",
        .bool => "i1",
        .void => "void",
        .identifer, .undefined => "i32", // fallback
    };
    try self.emit(type_str);
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
        \\define i32 @main() {
        \\entry:
        \\    ret i32 42
        \\}
        \\
    , result);
}

test "return with arithmetic" {
    const result = try testGenerate("fn calc() i32 { return 1 + 2; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @calc() {
        \\entry:
        \\    %2 = add i32 1, 2
        \\    ret i32 %2
        \\}
        \\
    , result);
}

test "complex arithmetic" {
    const result = try testGenerate("fn calc() i32 { return 2 * 3 + 4; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @calc() {
        \\entry:
        \\    %2 = mul i32 2, 3
        \\    %4 = add i32 %2, 4
        \\    ret i32 %4
        \\}
        \\
    , result);
}

test "function with parameter" {
    const result = try testGenerate("fn square(x: i32) i32 { return x * x; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @square(i32 %p0) {
        \\entry:
        \\    %2 = mul i32 %p0, %p0
        \\    ret i32 %2
        \\}
        \\
    , result);
}

test "function with two parameters" {
    const result = try testGenerate("fn add(a: i32, b: i32) i32 { return a + b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @add(i32 %p0, i32 %p1) {
        \\entry:
        \\    %2 = add i32 %p0, %p1
        \\    ret i32 %2
        \\}
        \\
    , result);
}

test "parameter with arithmetic" {
    const result = try testGenerate("fn double(n: i32) i32 { return n * 2; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @double(i32 %p0) {
        \\entry:
        \\    %2 = mul i32 %p0, 2
        \\    ret i32 %2
        \\}
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
        \\define i32 @foo() {
        \\entry:
        \\    ret i32 10
        \\}
        \\
    , result);
}

test "variable with computation" {
    const result = try testGenerate(
        \\fn calc(n: i32) i32 {
        \\  const result = n + 1;
        \\  return result;
        \\}
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @calc(i32 %p0) {
        \\entry:
        \\    %2 = add i32 %p0, 1
        \\    ret i32 %2
        \\}
        \\
    , result);
}

test "subtraction" {
    const result = try testGenerate("fn sub(a: i32, b: i32) i32 { return a - b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @sub(i32 %p0, i32 %p1) {
        \\entry:
        \\    %2 = sub i32 %p0, %p1
        \\    ret i32 %2
        \\}
        \\
    , result);
}

test "division" {
    const result = try testGenerate("fn div(a: i32, b: i32) i32 { return a / b; }");
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @div(i32 %p0, i32 %p1) {
        \\entry:
        \\    %2 = sdiv i32 %p0, %p1
        \\    ret i32 %2
        \\}
        \\
    , result);
}

test "multiple functions" {
    const result = try testGenerate(
        \\fn add(a: i32, b: i32) i32 { return a + b; }
        \\fn main() i32 { return 0; }
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @add(i32 %p0, i32 %p1) {
        \\entry:
        \\    %2 = add i32 %p0, %p1
        \\    ret i32 %2
        \\}
        \\
        \\define i32 @main() {
        \\entry:
        \\    ret i32 0
        \\}
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
        \\define i32 @foo() {
        \\entry:
        \\    ret i32 42
        \\}
        \\
        \\define i32 @main() {
        \\entry:
        \\    %0 = call i32 @foo()
        \\    ret i32 %0
        \\}
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
        \\define i32 @add(i32 %p0, i32 %p1) {
        \\entry:
        \\    %2 = add i32 %p0, %p1
        \\    ret i32 %2
        \\}
        \\
        \\define i32 @main() {
        \\entry:
        \\    %2 = call i32 @add(i32 3, i32 5)
        \\    ret i32 %2
        \\}
        \\
    , result);
}

test "nested function calls" {
    const result = try testGenerate(
        \\fn square(x: i32) i32 { return x * x; }
        \\fn add(a: i32, b: i32) i32 { return a + b; }
        \\fn main() i32 { return add(square(2), square(3)); }
    );
    defer testing.allocator.free(result);

    try testing.expectEqualStrings(
        \\define i32 @square(i32 %p0) {
        \\entry:
        \\    %2 = mul i32 %p0, %p0
        \\    ret i32 %2
        \\}
        \\
        \\define i32 @add(i32 %p0, i32 %p1) {
        \\entry:
        \\    %2 = add i32 %p0, %p1
        \\    ret i32 %2
        \\}
        \\
        \\define i32 @main() {
        \\entry:
        \\    %1 = call i32 @square(i32 2)
        \\    %3 = call i32 @square(i32 3)
        \\    %4 = call i32 @add(i32 %1, i32 %3)
        \\    ret i32 %4
        \\}
        \\
    , result);
}
