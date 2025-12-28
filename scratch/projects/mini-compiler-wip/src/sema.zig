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
// e. Error
// error contain the instruction idx that create this error,
// and contain the error message
//
// f. function return type
// I should add return type to the ast for the function
// and also to add it to the sema
// and when the return type of the function exist i should compare the defined with the actual
// how to find the actual
// i should take the instref from the return type and look into that ref and find the type for it
// which mean i need to loop on all the zir and add them one by one type to some list and then to referece them
//
// nouns: Type
//
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

    pub fn getSourceLine(self: Error, source: []const u8) ![]const u8 {
        const line_num = self.getToken().line;
        var lines = mem.splitScalar(u8, source, '\n');
        for (1..line_num) |_| _ = lines.next();
        return lines.next() orelse "";
    }

    pub fn getCaret(self: Error, allocator: Allocator) ![]const u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .empty;
        const writer = buffer.writer(allocator);
        const col_num = self.getToken().col;
        try writer.writeByteNTimes(' ', col_num - 1);
        try writer.writeAll("^");
        return buffer.toOwnedSlice(allocator);
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

    pub fn toString(self: Error, allocator: Allocator, source: []const u8) ![]const u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .empty;
        const writer = buffer.writer(allocator);

        const message = try self.getMessage(allocator);
        const source_line = try self.getSourceLine(source);
        const caretLine = try self.getCaret(allocator);

        try writer.writeAll("error: ");
        try writer.print("{s}\n", .{message});
        try writer.print("{s}\n", .{source_line});
        try writer.print("{s}\n", .{caretLine});

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

fn errorsToString(allocator: Allocator, errors: []Error, source: []const u8) ![]const u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    const writer = buffer.writer(allocator);

    for (errors) |_error| {
        const message = try _error.toString(allocator, source);
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
    const result = try errorsToString(allocator, errors, input);
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
    const result = try errorsToString(allocator, errors, input);
    try testing.expectEqualStrings(
        \\error: 1:19 undefined variable "x"
        \\fn foo() { return x; }
        \\                  ^
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
    const result = try errorsToString(allocator, errors, input);
    try testing.expectEqualStrings(
        \\error: 1:31 duplicate declaration "x"
        \\fn foo() { const x = 1; const x = 2; }
        \\                              ^
        \\
    , result);
}

test "multiline - undefined on line 3" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\fn foo() {
        \\  const x = 1;
        \\  return y;
        \\}
    ;

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const errors = try analyzeProgram(allocator, program);
    const result = try errorsToString(allocator, errors, input);
    try testing.expectEqualStrings(
        \\error: 3:10 undefined variable "y"
        \\  return y;
        \\         ^
        \\
    , result);
}

test "multiline - multiple errors on different lines" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\fn foo() {
        \\  return b;
        \\  const b = 2;
        \\}
    ;

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const errors = try analyzeProgram(allocator, program);
    const result = try errorsToString(allocator, errors, input);
    try testing.expectEqualStrings(
        \\error: 2:10 undefined variable "b"
        \\  return b;
        \\         ^
        \\
    , result);
}

test "function return type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\fn foo() i32 {
        \\  return 1;
        \\}
    ;

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const errors = try analyzeProgram(allocator, program);
    const result = try errorsToString(allocator, errors, input);
    try testing.expectEqualStrings(
        \\
    , result);
}
