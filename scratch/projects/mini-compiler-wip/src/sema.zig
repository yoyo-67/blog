const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = mem.Allocator;

const ast_mod = @import("ast.zig");
const zir_mod = @import("zir.zig");
const Instruction = zir_mod.Instruction;
const Node = zir_mod.Node;
const Token = @import("token.zig");
const Type = @import("types.zig").Type;

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
    declared: std.StringArrayHashMapUnmanaged(Type),
    types: std.ArrayListUnmanaged(Type),

    pub fn init() Scope {
        return .{ .declared = .empty, .types = .empty };
    }

    pub fn contains(self: *const Scope, name: []const u8) bool {
        return self.declared.contains(name);
    }

    pub fn declare(self: *Scope, allocator: Allocator, name: []const u8, type_value: Type) !void {
        try self.declared.put(allocator, name, type_value);
    }

    pub fn getType(self: *Scope, name: []const u8) ?Type {
        return self.declared.get(name);
    }
};

fn analyzeProgram(allocator: Allocator, program: zir_mod.Program) ![]Error {
    var errors: std.ArrayListUnmanaged(Error) = .empty;
    for (program.functions()) |function| {
        const result = try analyzeFunction(allocator, function);
        const function_errors = result.errors;
        for (function_errors) |function_error| {
            try errors.append(allocator, function_error);
        }
    }

    return errors.toOwnedSlice(allocator);
}

const AnalyzeFunctionResult = struct {
    errors: []Error,
    types: []Type,
};

fn analyzeFunction(allocator: Allocator, function: zir_mod.Function) !AnalyzeFunctionResult {
    var errors: std.ArrayListUnmanaged(Error) = .empty;
    var scope = Scope.init();

    for (function.instructions()) |instruction| {
        switch (instruction) {
            .decl => |inst| {
                if (Error.checkDuplicate(inst.name, &scope)) {
                    try errors.append(allocator, .{ .duplicate = .{ .name = inst.name, .node = inst.node } });
                } else {
                    const value_type = scope.types.items[inst.value];
                    try scope.declare(allocator, inst.name, value_type);
                    try scope.types.append(allocator, value_type);
                }
            },
            .decl_ref => |inst| {
                if (Error.checkUndefined(inst.name, &scope)) {
                    try errors.append(allocator, .{ .undefined = .{ .name = inst.name, .node = inst.node } });
                }

                const value_type = scope.getType(inst.name) orelse .undefined;
                try scope.types.append(allocator, value_type);
            },
            .literal => |lit| {
                try scope.types.append(allocator, lit.value.getType());
            },
            .add, .div, .mul, .sub => {
                try scope.types.append(allocator, .i32);
            },
            .param_ref => |inst| {
                const param = function.params[inst.value];
                try scope.types.append(allocator, param.type);
            },
            .return_stmt => |inst| {
                const return_type = scope.types.items[inst.value];
                try scope.types.append(allocator, return_type);
            },
        }
    }

    return .{ .errors = try errors.toOwnedSlice(allocator), .types = try scope.types.toOwnedSlice(allocator) };
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

    // Assert the return type is i32
    try testing.expectEqual(@as(usize, 1), program.functions().len);
    try testing.expectEqual(.i32, program.functions()[0].return_type.?);
}

test "infer type - constant is i32" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn foo() { return 42; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);

    // %0 = literal(42) -> i32
    // %1 = ret(%0)      -> i32
    try testing.expectEqual(@as(usize, 2), result.types.len);
    try testing.expectEqual(.i32, result.types[0]); // constant
    try testing.expectEqual(.i32, result.types[1]); // return
}

test "infer type - param_ref uses param type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn foo(x: i32) { return x; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);

    // %0 = param_ref(0) -> i32 (from param x: i32)
    // %1 = ret(%0)      -> i32
    try testing.expectEqual(@as(usize, 2), result.types.len);
    try testing.expectEqual(.i32, result.types[0]); // param_ref
    try testing.expectEqual(.i32, result.types[1]); // return
}

test "infer type - arithmetic expressions are i32" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn foo(a: i32, b: i32) { return a + b * 2; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);

    // %0 = param_ref(0)    -> i32
    // %1 = param_ref(1)    -> i32
    // %2 = literal(2)     -> i32
    // %3 = mul(%1, %2)     -> i32
    // %4 = add(%0, %3)     -> i32
    // %5 = ret(%4)         -> i32
    try testing.expectEqual(@as(usize, 6), result.types.len);
    for (result.types) |t| {
        try testing.expectEqual(.i32, t);
    }
}

test "infer type - variable declaration inherits value type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\fn foo() {
        \\  const x = 10;
        \\  return x;
        \\}
    ;

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);

    // %0 = literal(10)    -> i32
    // %1 = decl("x", %0)   -> i32 (inherits from constant)
    // %2 = decl_ref("x")   -> i32 (looks up from scope)
    // %3 = ret(%2)         -> i32
    try testing.expectEqual(@as(usize, 4), result.types.len);
    try testing.expectEqual(.i32, result.types[0]); // constant
    try testing.expectEqual(.i32, result.types[1]); // decl
    try testing.expectEqual(.i32, result.types[2]); // decl_ref
    try testing.expectEqual(.i32, result.types[3]); // return
}

test "infer type - undefined variable has type_error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn foo() { return x; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);

    // %0 = decl_ref("x")   -> undefined (undefined)
    // %1 = ret(%0)         ->undefined
    try testing.expectEqual(@as(usize, 2), result.types.len);
    try testing.expectEqual(.undefined, result.types[0]); // undefined decl_ref
    try testing.expectEqual(.undefined, result.types[1]); // return inherits type_error
}

fn typedZirToString(allocator: Allocator, function: zir_mod.Function, types: []const Type) ![]const u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    const writer = buffer.writer(allocator);
    for (function.instructions(), 0..) |inst, idx| {
        try inst.toString(idx, writer);
        try writer.print(" : {s}\n", .{@tagName(types[idx])});
    }

    return buffer.toOwnedSlice(allocator);
}

test "typed zir - constant returns i32" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn foo() { return 42; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);
    const typed_zir = try typedZirToString(allocator, function, result.types);

    try testing.expectEqualStrings(
        \\%0 = literal(42) : i32
        \\%1 = ret(%0) : i32
        \\
    , typed_zir);
}

test "typed zir - param and arithmetic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn add(a: i32, b: i32) { return a + b; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);
    const typed_zir = try typedZirToString(allocator, function, result.types);

    try testing.expectEqualStrings(
        \\%0 = param_ref(0) : i32
        \\%1 = param_ref(1) : i32
        \\%2 = add(%0, %1) : i32
        \\%3 = ret(%2) : i32
        \\
    , typed_zir);
}

test "typed zir - variable declaration and reference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\fn foo() {
        \\  const x = 10;
        \\  const y = false;
        \\  return y;
        \\}
    ;

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);
    const typed_zir = try typedZirToString(allocator, function, result.types);

    try testing.expectEqualStrings(
        \\%0 = literal(10) : i32
        \\%1 = decl("x", %0) : i32
        \\%2 = literal(false) : bool
        \\%3 = decl("y", %2) : bool
        \\%4 = decl_ref("y") : bool
        \\%5 = ret(%4) : bool
        \\
    , typed_zir);
}

test "typed zir - undefined variable shows undefined type" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "fn foo() { return unknown_var; }";

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);
    const typed_zir = try typedZirToString(allocator, function, result.types);

    try testing.expectEqualStrings(
        \\%0 = decl_ref("unknown_var") : undefined
        \\%1 = ret(%0) : undefined
        \\
    , typed_zir);
}

test "typed zir - float literal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\fn foo() {
        \\  const x = 3.14;
        \\  return x;
        \\}
    ;

    const tree = try ast_mod.parseExpr(&arena, input);
    const program = try zir_mod.generateProgram(allocator, &tree);
    const function = program.functions()[0];
    const result = try analyzeFunction(allocator, function);
    const typed_zir = try typedZirToString(allocator, function, result.types);

    try testing.expectEqualStrings(
        \\%0 = literal(3.14) : f64
        \\%1 = decl("x", %0) : f64
        \\%2 = decl_ref("x") : f64
        \\%3 = ret(%2) : f64
        \\
    , typed_zir);
}
