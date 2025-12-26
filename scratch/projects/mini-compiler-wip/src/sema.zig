const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const ast_mod = @import("ast.zig");
const zir_mod = @import("zir.zig");
const Instruction = zir_mod.Instruction;

const assert = std.debug.assert;

// what I try to achive
// a. to have input as string
// b. parse it
// c. zir it
// d. use the instructions and check them
// e. if there is errors I wanted to see them, and to output error message and correct location on the source.
//
// let revist the source location later on.
// how to build it:
//
// we need to see what is the nouns.
// a. Program
// logic + behaviors:
// loop over the functions and analyze them and return []errors
//
// b. Function
// behavior:
// analyze the function and output []errors
//
// c. Instructions
// for each instruction you need to check against previous instructions
// and to see if the instruction is valid or invlid (when varible is already declared or the variable is undefined)
//
// d. Scope
// each scope has it own set of declared variable.
//
// d. Error
// error contain the instruction idx that create this error,
// and contain the error message
//
//

const Error = struct {
    kind: Kind,
    name: []const u8,

    pub const Kind = enum { undefined, duplicate };

    pub fn getMessage(self: Error) []const u8 {
        return switch (self.kind) {
            .undefined => "undefined variable",
            .duplicate => "duplicate declaration",
        };
    }

    /// Returns error if name is NOT in scope (undefined)
    pub fn checkUndefined(name: []const u8, scope: *const Scope) ?Error {
        if (!scope.contains(name)) {
            return .{ .kind = .undefined, .name = name };
        }
        return null;
    }

    /// Returns error if name IS already in scope (duplicate)
    pub fn checkDuplicate(name: []const u8, scope: *const Scope) ?Error {
        if (scope.contains(name)) {
            return .{ .kind = .duplicate, .name = name };
        }
        return null;
    }

    pub fn toString(self: Error, allocator: Allocator) ![]const u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .empty;
        const writer = buffer.writer(allocator);

        const message = self.getMessage();

        try writer.writeAll("error: ");
        try writer.print("{s} ", .{message});
        try writer.print("\"{s}\"", .{self.name});

        return try buffer.toOwnedSlice(allocator);
    }
};

const Scope = struct {
    declared: std.StringArrayHashMapUnmanaged(void),

    pub fn init() Scope {
        return .{ .declared = .empty };
    }

    pub fn contains(self: *const Scope, name: []const u8) bool {
        return self.declared.contains(name);
    }

    pub fn declare(self: *Scope, allocator: Allocator, name: []const u8) !void {
        try self.declared.put(allocator, name, {});
    }
};

fn analyzeProgram(allocator: Allocator, program: zir_mod.Program) ![]Error {
    var errors: std.ArrayListUnmanaged(Error) = .empty;
    for (program.functions()) |function| {
        const function_errors = try analyzeFunction(allocator, function);
        for (function_errors) |function_error| {
            try errors.append(allocator, function_error);
        }
    }

    return errors.toOwnedSlice(allocator);
}

fn analyzeFunction(allocator: Allocator, function: zir_mod.Function) ![]Error {
    var errors: std.ArrayListUnmanaged(Error) = .empty;
    var scope = Scope.init();

    for (function.instructions()) |instruction| {
        switch (instruction) {
            .decl => |inst| {
                if (Error.checkDuplicate(inst.name, &scope)) |err| {
                    try errors.append(allocator, err);
                } else {
                    try scope.declare(allocator, inst.name);
                }
            },
            .decl_ref => |inst| {
                if (Error.checkUndefined(inst.name, &scope)) |err| {
                    try errors.append(allocator, err);
                }
            },
            else => {},
        }
    }

    return errors.toOwnedSlice(allocator);
}

fn errorsToString(allocator: Allocator, errors: []Error) ![]const u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    const writer = buffer.writer(allocator);

    for (errors) |_error| {
        const message = try _error.toString(allocator);
        try writer.writeAll(message);
    }

    return buffer.toOwnedSlice(allocator);
}

test "valid code - no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\fn calc(n: i32) {
        \\const result = n + 1;
        \\return result;
        \\}
    ;

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const errors = try analyzeProgram(allocator, program);
    const result = try errorsToString(allocator, errors);
    try testing.expectEqualStrings(
        \\
    , result);
}

test "undefined variable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn foo() { return x; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const errors = try analyzeProgram(allocator, program);
    const result = try errorsToString(allocator, errors);
    try testing.expectEqualStrings(
        \\error: undefined variable "x"
        \\
    , result);
}

test "duplicate declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn foo() { const x = 1; const x = 2; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const errors = try analyzeProgram(allocator, program);
    const result = try errorsToString(allocator, errors);
    try testing.expectEqualStrings(
        \\error: duplicate declaration "x"
        \\
    , result);
}
//
// test "undefined variable psas" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//
//     var sema = Sema{ .errors = .empty };
//
//     const result = try sema.testAnalyze(&arena, "fn foo() { const x = 3; return x; }");
//
//     try testing.expectEqualStrings(
//         \\
//     , result);
// }
//
// test "declaration" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//
//     var sema = Sema{ .errors = .empty };
//
//     const result = try sema.testAnalyze(&arena, "fn foo() { const x = 3; const  x = 3; }");
//
//     try testing.expectEqualStrings(
//         \\error: duplicate declaration "x"
//         \\
//     , result);
// }

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
