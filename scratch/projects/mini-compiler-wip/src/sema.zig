const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const ast_mod = @import("ast.zig");
const zir_mod = @import("zir.zig");
const Instruction = zir_mod.Instruction;

pub const Error = union(enum) {
    undefined_variable: struct { name: []const u8, inst: *const Instruction },
    duplicate_declaration: struct { name: []const u8, inst: *const Instruction },

    pub fn toString(self: Error, allocator: mem.Allocator, source: []const u8) ![]const u8 {
        const token = self.getToken();
        const message = try self.getMessage(allocator);
        const line_content = getLine(source, token.line);
        const caret = try makeCaretLine(allocator, token.col);

        return try std.fmt.allocPrint(allocator, "{d}:{d}: error: {s}\n{s}\n{s}\n", .{
            token.line,
            token.col,
            message,
            line_content,
            caret,
        });
    }

    fn getToken(self: Error) *const @import("token.zig") {
        return switch (self) {
            .undefined_variable => |e| e.inst.decl_ref.node.identifier_ref.token,
            .duplicate_declaration => |e| e.inst.decl.node.identifier.token,
        };
    }

    fn getMessage(self: Error, allocator: mem.Allocator) ![]const u8 {
        return switch (self) {
            .undefined_variable => |e| try std.fmt.allocPrint(allocator, "undefined variable \"{s}\"", .{e.name}),
            .duplicate_declaration => |e| try std.fmt.allocPrint(allocator, "duplicate declaration \"{s}\"", .{e.name}),
        };
    }
};

pub fn analyzeProgram(allocator: mem.Allocator, program: *const zir_mod.Program) ![]Error {
    var all_errors: std.ArrayListUnmanaged(Error) = .empty;
    for (program.functions()) |*func| {
        const errors = try analyzeFunction(allocator, func);
        try all_errors.appendSlice(allocator, errors);
    }
    return all_errors.toOwnedSlice(allocator);
}

fn analyzeFunction(allocator: mem.Allocator, func: *const zir_mod.Function) ![]Error {
    var errors: std.ArrayListUnmanaged(Error) = .empty;

    // tracks: declared names -> their type
    var names: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer names.deinit(allocator);

    // tracks: instruction index -> result type
    var inst_types: std.ArrayListUnmanaged(?[]const u8) = .empty;
    defer inst_types.deinit(allocator);

    // register parameters
    for (func.params) |param| {
        try names.put(allocator, param.name, param.type);
    }

    // analyze each instruction
    for (0..func.instructionCount()) |i| {
        const inst = func.instructionAt(i);
        const result_type: ?[]const u8 = switch (inst.*) {
            .constant => "i32",
            .param_ref => |idx| func.params[idx].type,
            .decl => |d| blk: {
                if (names.contains(d.name)) {
                    try errors.append(allocator, .{ .duplicate_declaration = .{ .name = d.name, .inst = inst } });
                } else {
                    const value_type = if (d.value < inst_types.items.len) inst_types.items[d.value] orelse "i32" else "i32";
                    try names.put(allocator, d.name, value_type);
                }
                break :blk null;
            },
            .decl_ref => |d| names.get(d.name) orelse blk: {
                try errors.append(allocator, .{ .undefined_variable = .{ .name = d.name, .inst = inst } });
                break :blk null;
            },
            .add, .sub, .mul, .div, .return_stmt => null,
        };
        try inst_types.append(allocator, result_type);
    }

    return errors.toOwnedSlice(allocator);
}

pub fn errorsToString(allocator: mem.Allocator, errors: []const Error, source: []const u8) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    for (errors) |err| {
        try buf.appendSlice(allocator, try err.toString(allocator, source));
    }
    return buf.toOwnedSlice(allocator);
}

fn getLine(source: []const u8, line_num: usize) []const u8 {
    var lines = mem.splitScalar(u8, source, '\n');
    for (1..line_num) |_| _ = lines.next();
    return lines.next() orelse "";
}

fn makeCaretLine(allocator: mem.Allocator, col: usize) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    // col is 1-based, so we need col-1 spaces before the caret
    const spaces = if (col > 0) col - 1 else 0;
    try buf.appendNTimes(allocator, ' ', spaces);
    try buf.append(allocator, '^');
    return buf.toOwnedSlice(allocator);
}

// Tests

fn testAnalyze(arena: *std.heap.ArenaAllocator, input: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    const tree = try ast_mod.parseExpr(arena, input);
    const tree_ptr = try allocator.create(zir_mod.Node);
    tree_ptr.* = tree;
    const program = try zir_mod.generateProgram(allocator, tree_ptr);
    const errors = try analyzeProgram(allocator, &program);
    return errorsToString(allocator, errors, input);
}

test "undefined variable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testAnalyze(&arena, "fn foo() { return x; }");

    try testing.expectEqualStrings(
        \\1:19: error: undefined variable "x"
        \\fn foo() { return x; }
        \\                  ^
        \\
    , result);
}

test "duplicate declaration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testAnalyze(&arena, "fn foo() { const x = 1; const x = 2; }");

    try testing.expectEqualStrings(
        \\1:31: error: duplicate declaration "x"
        \\fn foo() { const x = 1; const x = 2; }
        \\                              ^
        \\
    , result);
}

test "no errors - valid code" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testAnalyze(&arena, "fn foo() { const x = 10; return x; }");

    try testing.expectEqualStrings("", result);
}

test "parameter usage is valid" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testAnalyze(&arena, "fn square(x: i32) { return x * x; }");

    try testing.expectEqualStrings("", result);
}

test "multiple errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testAnalyze(&arena, "fn foo() { const x = a + b; }");

    try testing.expectEqualStrings(
        \\1:22: error: undefined variable "a"
        \\fn foo() { const x = a + b; }
        \\                     ^
        \\1:26: error: undefined variable "b"
        \\fn foo() { const x = a + b; }
        \\                         ^
        \\
    , result);
}

test "multiple undefined in function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const result = try testAnalyze(&arena, "fn foo() { return x + y; }");

    try testing.expectEqualStrings(
        \\1:19: error: undefined variable "x"
        \\fn foo() { return x + y; }
        \\                  ^
        \\1:23: error: undefined variable "y"
        \\fn foo() { return x + y; }
        \\                      ^
        \\
    , result);
}

