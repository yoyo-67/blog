const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const ast_mod = @import("ast.zig");
const zir_mod = @import("zir.zig");
const Instruction = zir_mod.Instruction;

errors: std.ArrayListUnmanaged(Error),

const Sema = @This();

const Error = union(enum) {
    undefined_variable: struct { name: []const u8, instruction: *const Instruction },
    duplicate_declaration: struct { name: []const u8, instruction: *const Instruction },

    pub fn toString(self: Error, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "error: {s}", .{try self.getMessage(allocator)});
    }

    pub fn getMessage(self: Error, allocator: Allocator) ![]const u8 {
        return switch (self) {
            .duplicate_declaration => |e| std.fmt.allocPrint(allocator, "duplicate declaration \"{s}\"", .{e.name}),
            .undefined_variable => |e| std.fmt.allocPrint(allocator, "undefined variable \"{s}\"", .{e.name}),
        };
    }
};

fn testAnalyze(self: *Sema, arena: *std.heap.ArenaAllocator, input: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    const tree = try ast_mod.parseExpr(arena, input);
    const zir = try zir_mod.generateProgram(allocator, &tree);

    const declerationSet = std.StringArrayHashMap(void).init(allocator);

    for (zir.functions()) |func| {
        const instructions = func.instructions();
        for (instructions) |*instruction| {
            switch (instruction.*) {
                .decl => |val| {
                    if (declerationSet.contains(val.name)) {
                        try self.errors.append(allocator, .{ .duplicate_declaration = .{ .name = val.name, .instruction = instruction } });
                    }
                },
                .decl_ref => |val| {
                    if (!declerationSet.contains(val.name)) {
                        try self.errors.append(allocator, .{ .undefined_variable = .{ .name = val.name, .instruction = instruction } });
                    }
                },
                else => {},
            }
        }
    }

    return try self.errorsToString(allocator);
}

fn errorsToString(self: *Sema, allocator: Allocator) ![]const u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    const writer = buffer.writer(allocator);

    for (self.errors.items) |error_item| {
        try writer.writeAll(try error_item.toString(allocator));
        try writer.writeAll("\n");
    }

    return buffer.toOwnedSlice(allocator);
}

test "undefined variable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var sema = Sema{ .errors = .empty };

    const result = try sema.testAnalyze(&arena, "fn foo() { return x; }");

    try testing.expectEqualStrings(
        \\error: undefined variable "x"
        \\
    , result);

    // try testing.expectEqualStrings(
    //     \\1:19: error: undefined variable "x"
    //     \\fn foo() { return x; }
    //     \\                  ^
    //     \\
    // , result);
}

// test "duplicate declaration" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//
//     const result = try testAnalyze(&arena, "fn foo() { const x = 1; const x = 2; }");
//
//     try testing.expectEqualStrings(
//         \\1:31: error: duplicate declaration "x"
//         \\fn foo() { const x = 1; const x = 2; }
//         \\                              ^
//         \\
//     , result);
// }
//
// test "no errors - valid code" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//
//     const result = try testAnalyze(&arena, "fn foo() { const x = 10; return x; }");
//
//     try testing.expectEqualStrings("", result);
// }
//
// test "parameter usage is valid" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//
//     const result = try testAnalyze(&arena, "fn square(x: i32) { return x * x; }");
//
//     try testing.expectEqualStrings("", result);
// }
//
// test "multiple errors" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//
//     const result = try testAnalyze(&arena, "fn foo() { const x = a + b; }");
//
//     try testing.expectEqualStrings(
//         \\1:22: error: undefined variable "a"
//         \\fn foo() { const x = a + b; }
//         \\                     ^
//         \\1:26: error: undefined variable "b"
//         \\fn foo() { const x = a + b; }
//         \\                         ^
//         \\
//     , result);
// }
//
// test "multiple undefined in function" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//
//     const result = try testAnalyze(&arena, "fn foo() { return x + y; }");
//
//     try testing.expectEqualStrings(
//         \\1:19: error: undefined variable "x"
//         \\fn foo() { return x + y; }
//         \\                  ^
//         \\1:23: error: undefined variable "y"
//         \\fn foo() { return x + y; }
//         \\                      ^
//         \\
//     , result);
// }
