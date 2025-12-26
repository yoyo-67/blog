const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const ast_mod = @import("ast.zig");
const zir_mod = @import("zir.zig");
const Instruction = zir_mod.Instruction;
const Node = zir_mod.Node;
const Token = @import("token.zig");

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

const Error = union(enum) {
    undefined: struct {
        name: []const u8,
        node: *const Node,
    },
    duplicate: struct {
        name: []const u8,
        node: *const Node,
    },

    pub fn getMessage(self: Error, allocator: Allocator) ![]const u8 {
        return switch (self) {
            .undefined => |err| try std.fmt.allocPrint(allocator, "{s} undefined variable \"{s}\"", .{ try self.getLocation(allocator), err.name }),
            .duplicate => |err| try std.fmt.allocPrint(allocator, "{s} duplicate declaration \"{s}\"", .{ try self.getLocation(allocator), err.name }),
        };
    }

    pub fn getLocation(self: Error, allocator: Allocator) ![]const u8 {
        const token = self.getToken();
        return try std.fmt.allocPrint(allocator, "{d}:{d}", .{ token.line, token.col });
    }

    pub fn getSourceLine(self: Error, allocator: Allocator, source: []const u8) ![]const u8 {
        _ = allocator; // autofix
        const line_num = self.getToken().line;
        const lines = mem.splitScalar(u8, source, "\n");
        for (1..line_num) |_| _ = lines.next();
        return lines.next() orelse "";
    }

    pub fn getToken(self: Error) *const Token {
        return switch (self) {
            .undefined => |val| val.node.*.identifier_ref.token,
            .duplicate => |val| val.node.*.identifier.token,
        };
    }

    pub fn checkUndefined(name: []const u8, scope: *const Scope) bool {
        if (!scope.contains(name)) {
            return true;
        }
        return false;
    }

    pub fn checkDuplicate(name: []const u8, scope: *const Scope) bool {
        if (scope.contains(name)) {
            return true;
        }
        return false;
    }

    pub fn toString(self: Error, allocator: Allocator) ![]const u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .empty;
        const writer = buffer.writer(allocator);

        const message = try self.getMessage(allocator);

        try writer.writeAll("error: ");
        try writer.print("{s}", .{message});

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
                if (Error.checkDuplicate(inst.name, &scope)) {
                    try errors.append(allocator, .{ .duplicate = .{ .name = inst.name, .node = inst.node } });
                } else {
                    try scope.declare(allocator, inst.name);
                }
            },
            .decl_ref => |inst| {
                if (Error.checkUndefined(inst.name, &scope)) {
                    try errors.append(allocator, .{ .undefined = .{ .name = inst.name, .node = inst.node } });
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
        try writer.writeAll("\n");
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
        \\error: 1:19 undefined variable "x"
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
        \\error: 1:31 duplicate declaration "x"
        \\
    , result);
}

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
