const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const zir_mod = @import("zir.zig");
const ast_mod = @import("ast.zig");
const Value = @import("types.zig").Value;

const Gen = @This();

output: std.ArrayListUnmanaged(u8),

pub fn init() Gen {
    return .{
        .output = .empty,
    };
}

pub fn writer(self: *Gen, alloc: Allocator) std.ArrayListUnmanaged(u8).Writer {
    return self.output.writer(alloc);
}

pub fn generate(self: *Gen, alloc: Allocator, program: zir_mod.Program) !void {
    for (program.functions()) |func| {
        try self.generateFunction(alloc, func);
        try self.writer(alloc).writeAll("\n");
    }
}

pub fn generateFunction(self: *Gen, alloc: Allocator, function: zir_mod.Function) !void {
    try self.generateGlobal(alloc, function);
    try self.generateLabel(alloc, function);
    try self.generateProlgue(alloc);
    for (function.instructions()) |inst| {
        switch (inst) {
            .return_stmt => |val| {
                _ = val; // autofix
                try self.generateEpilogue(alloc);
            },
            else => {},
        }
    }
}

// everyfunction start with .global _name of the fn
// _name of the fun:
//     put the link
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp

pub fn generateGlobal(self: *Gen, alloc: Allocator, function: zir_mod.Function) !void {
    try self.writer(alloc).print(".global _{s}", .{function.name});
    try self.writer(alloc).writeAll("\n");
}

pub fn generateLabel(self: *Gen, alloc: Allocator, function: zir_mod.Function) !void {
    try self.writer(alloc).print("_{s}:", .{function.name});
    try self.writer(alloc).writeAll("\n");
}

pub fn generateProlgue(self: *Gen, alloc: Allocator) !void {
    try self.writer(alloc).writeAll("    stp x29, x30, [sp, #-16]!");
    try self.writer(alloc).writeAll("\n");
    try self.writer(alloc).writeAll("    mov x29, sp");
    try self.writer(alloc).writeAll("\n");
}

pub fn generateEpilogue(self: *Gen, alloc: Allocator) !void {
    try self.writer(alloc).writeAll("    ldp x29, x30, [sp], #16");
    try self.writer(alloc).writeAll("\n");
    try self.writer(alloc).writeAll("    ret");
}

fn testGenerate(arena: *std.heap.ArenaAllocator, input: []const u8) ![]const u8 {
    const tree = try ast_mod.parseExpr(arena, input);
    const alloc = arena.allocator();
    const program = try zir_mod.generateProgram(alloc, &tree);

    var gen = Gen.init();
    try gen.generate(alloc, program);
    return try gen.output.toOwnedSlice(alloc);
}

test "simple return constant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = try testGenerate(&arena, "fn main() i32 { return 42; }");
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

// test "return with arithmetic" {
//     const result = try testGenerate("fn calc() i32 { return 1 + 2; }");
//     defer testing.allocator.free(result);
//
//     try testing.expectEqualStrings(
//         \\.global _calc
//         \\_calc:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    mov w16, #1
//         \\    add w10, w16, #2
//         \\    mov w0, w10
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\
//     , result);
// }
//
// test "function with parameter" {
//     const result = try testGenerate("fn square(x: i32) i32 { return x * x; }");
//     defer testing.allocator.free(result);
//
//     try testing.expectEqualStrings(
//         \\.global _square
//         \\_square:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    mul w10, w0, w0
//         \\    mov w0, w10
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\
//     , result);
// }
//
// test "function with two parameters" {
//     const result = try testGenerate("fn add(a: i32, b: i32) i32 { return a + b; }");
//     defer testing.allocator.free(result);
//
//     try testing.expectEqualStrings(
//         \\.global _add
//         \\_add:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    add w10, w0, w1
//         \\    mov w0, w10
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\
//     , result);
// }
//
// test "subtraction" {
//     const result = try testGenerate("fn sub(a: i32, b: i32) i32 { return a - b; }");
//     defer testing.allocator.free(result);
//
//     try testing.expectEqualStrings(
//         \\.global _sub
//         \\_sub:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    sub w10, w0, w1
//         \\    mov w0, w10
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\
//     , result);
// }
//
// test "division" {
//     const result = try testGenerate("fn div(a: i32, b: i32) i32 { return a / b; }");
//     defer testing.allocator.free(result);
//
//     try testing.expectEqualStrings(
//         \\.global _div
//         \\_div:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    sdiv w10, w0, w1
//         \\    mov w0, w10
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\
//     , result);
// }
//
// test "variable declaration and use" {
//     const result = try testGenerate(
//         \\fn foo() i32 {
//         \\  const x = 10;
//         \\  return x;
//         \\}
//     );
//     defer testing.allocator.free(result);
//
//     try testing.expectEqualStrings(
//         \\.global _foo
//         \\_foo:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    mov w0, #10
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\
//     , result);
// }
//
// test "function call no args" {
//     const result = try testGenerate(
//         \\fn foo() i32 { return 42; }
//         \\fn main() i32 { return foo(); }
//     );
//     defer testing.allocator.free(result);
//
//     try testing.expectEqualStrings(
//         \\.global _foo
//         \\_foo:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    mov w0, #42
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\.global _main
//         \\_main:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    bl _foo
//         \\    mov w8, w0
//         \\    mov w0, w8
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\
//     , result);
// }
//
// test "function call with args" {
//     const result = try testGenerate(
//         \\fn add(a: i32, b: i32) i32 { return a + b; }
//         \\fn main() i32 { return add(3, 5); }
//     );
//     defer testing.allocator.free(result);
//
//     try testing.expectEqualStrings(
//         \\.global _add
//         \\_add:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    add w10, w0, w1
//         \\    mov w0, w10
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\.global _main
//         \\_main:
//         \\    stp x29, x30, [sp, #-16]!
//         \\    mov x29, sp
//         \\    mov w0, #3
//         \\    mov w1, #5
//         \\    bl _add
//         \\    mov w10, w0
//         \\    mov w0, w10
//         \\    ldp x29, x30, [sp], #16
//         \\    ret
//         \\
//         \\
//     , result);
// }
