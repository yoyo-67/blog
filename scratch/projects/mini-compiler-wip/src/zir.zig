const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const token_mod = @import("token.zig");
const ast_mod = @import("ast.zig");
const node_mod = @import("node.zig");
const Type = @import("types.zig").Type;
pub const Node = node_mod.Node;

pub const Zir = @This();

instructions: std.ArrayListUnmanaged(Instruction),
parameters: std.StringHashMapUnmanaged(u32),

pub fn init() Zir {
    return .{
        .instructions = .empty,
        .parameters = .empty,
    };
}

pub fn generate(self: *Zir, allocator: mem.Allocator, node: *const Node) !InstructionRef {
    switch (node.*) {
        .int_literal => |lit| return try self.emit(allocator, .{ .constant = .{ .value = lit.value, .node = node } }),
        .binary_op => |bin| {
            const lhs = try self.generate(allocator, bin.lhs);
            const rhs = try self.generate(allocator, bin.rhs);
            return switch (bin.op) {
                .plus => try self.emit(allocator, .{ .add = .{ .lhs = lhs, .rhs = rhs, .node = node } }),
                .minus => try self.emit(allocator, .{ .sub = .{ .lhs = lhs, .rhs = rhs, .node = node } }),
                .mul => try self.emit(allocator, .{ .mul = .{ .lhs = lhs, .rhs = rhs, .node = node } }),
                .div => try self.emit(allocator, .{ .div = .{ .lhs = lhs, .rhs = rhs, .node = node } }),
            };
        },
        .root => |root| {
            var last: InstructionRef = 0;
            for (root.decls) |*decl| {
                last = try self.generate(allocator, decl);
            }
            return last;
        },
        .identifier => |val| {
            if (self.parameters.contains(val.name)) {
                @panic("cannot re declare parameter");
            }
            const instruction_ref = try self.generate(allocator, val.value);
            return try self.emit(allocator, .{ .decl = .{
                .name = val.name,
                .value = instruction_ref,
                .node = node,
            } });
        },
        .return_stmt => |val| {
            const instructuion_ref = try self.generate(allocator, val.value);
            return try self.emit(allocator, .{ .return_stmt = .{ .value = instructuion_ref, .node = node } });
        },
        .identifier_ref => |val| {
            if (self.parameters.get(val.name)) |param_idx| {
                return try self.emit(allocator, .{
                    .param_ref = .{ .value = param_idx, .node = node },
                });
            }

            return try self.emit(allocator, .{ .decl_ref = .{ .name = val.name, .node = node } });
        },
        .fn_decl => |val| {
            // loop on the parameters and emit them.
            // then emit the decleration on the block
            var last: InstructionRef = 0;
            for (val.params, 0..) |param, idx| {
                try self.parameters.put(allocator, param.name, @intCast(idx));
            }

            for (val.block.decls) |*decl| {
                last = try self.generate(allocator, decl);
            }

            return last;
        },

        else => unreachable,
    }
}

fn emit(self: *Zir, allocator: mem.Allocator, instruction: Instruction) !InstructionRef {
    const idx: u32 = @intCast(self.instructions.items.len);
    try self.instructions.append(allocator, instruction);
    return idx;
}

fn toString(self: *Zir, allocator: mem.Allocator) ![]const u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    const writer = buffer.writer(allocator);
    for (self.instructions.items, 0..) |instruction, idx| {
        try instruction.toString(idx, writer);
        try writer.writeAll("\n");
    }
    return buffer.toOwnedSlice(allocator);
}

const InstructionRef = u32;

pub const Instruction = union(enum) {
    constant: struct {
        value: i32,
        node: *const Node,
    },
    add: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
        node: *const Node,
    },
    sub: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
        node: *const Node,
    },
    mul: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
        node: *const Node,
    },
    div: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
        node: *const Node,
    },
    decl: struct {
        name: []const u8,
        value: InstructionRef,
        node: *const Node,
    },
    decl_ref: struct {
        name: []const u8,
        node: *const Node,
    },
    return_stmt: struct {
        value: InstructionRef,
        node: *const Node,
    },
    param_ref: struct {
        value: u32,
        node: *const Node,
    },

    pub fn toString(self: Instruction, idx: usize, writer: anytype) !void {
        try writer.print("%{d} = ", .{idx});
        switch (self) {
            .constant => |val| try writer.print("constant({d})", .{val.value}),
            .add => |val| try writer.print("add(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .sub => |val| try writer.print("sub(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .mul => |val| try writer.print("mul(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .div => |val| try writer.print("div(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .decl => |val| try writer.print("decl(\"{s}\", %{d})", .{ val.name, val.value }),
            .decl_ref => |val| try writer.print("decl_ref(\"{s}\")", .{val.name}),
            .return_stmt => |val| try writer.print("ret(%{d})", .{val.value}),
            .param_ref => |val| try writer.print("param_ref({d})", .{val.value}),
        }
    }
};

fn deinit(self: *Zir, allocator: mem.Allocator) void {
    self.instructions.deinit(allocator);
    self.parameters.deinit(allocator);
}

pub const Program = struct {
    functions_list: std.ArrayListUnmanaged(Function),

    pub fn init() Program {
        return .{ .functions_list = .empty };
    }

    pub fn functions(self: *const Program) []const Function {
        return self.functions_list.items;
    }

    pub fn toString(self: *Program, allocator: mem.Allocator) ![]const u8 {
        var buffer: std.ArrayListUnmanaged(u8) = .empty;
        const writer = buffer.writer(allocator);
        for (self.functions_list.items, 0..) |*function, i| {
            if (i > 0) try writer.writeAll("\n");
            try function.toString(allocator, writer);
        }
        return try buffer.toOwnedSlice(allocator);
    }
};

pub const Function = struct {
    name: []const u8,
    return_type: ?Type,
    params: []const Node.Param,
    zir: Zir,

    pub fn instructions(self: *const Function) []const Instruction {
        return self.zir.instructions.items;
    }

    pub fn instructionAt(self: *const Function, idx: usize) *const Instruction {
        return &self.zir.instructions.items[idx];
    }

    pub fn instructionCount(self: *const Function) usize {
        return self.zir.instructions.items.len;
    }

    pub fn toString(self: *Function, allocator: mem.Allocator, writer: anytype) !void {
        _ = allocator;
        try writer.print("function \"{s}\":\n", .{self.name});
        try writer.writeAll("  params: [");
        for (self.params, 0..) |param, idx| {
            if (idx > 0) {
                try writer.writeAll(", ");
            }
            try writer.print("(\"{s}\", {s})", .{ param.name, @tagName(param.type) });
        }
        try writer.writeAll("]\n");
        const return_type_str = if (self.return_type) |t| @tagName(t) else "?";
        try writer.print("  return_type: {s}", .{return_type_str});
        try writer.writeAll("\n");
        try writer.writeAll("  body:\n");
        for (self.zir.instructions.items, 0..) |instruction, idx| {
            try writer.writeAll("    ");
            try instruction.toString(idx, writer);
            try writer.writeAll("\n");
        }
    }
};

// 1. i need to create generateProgram
pub fn generateProgram(allocator: mem.Allocator, node: *const Node) !Program {
    var functions: std.ArrayListUnmanaged(Function) = .empty;
    for (node.root.decls) |*decl| {
        if (decl.* == .fn_decl) {
            const fn_decl = try generateFunction(allocator, decl);
            try functions.append(allocator, fn_decl);
        }
    }

    return .{ .functions_list = functions };
}

pub fn generateFunction(allocator: mem.Allocator, node: *const Node) !Function {
    var zir = Zir.init();
    _ = try zir.generate(allocator, node);

    return .{
        .name = node.fn_decl.name,
        .params = node.fn_decl.params,
        .return_type = node.fn_decl.return_type,
        .zir = zir,
    };
}
// 2. the generateProgram will call to generate function for each function he see.
// 3. the generate functon will have name , params -> [name,type], instructions.
// 4. the toString on the generateProgram will call to each function and call toString on it and add new line.
// 5. the toString for each function will print:
//    function "<name>":
//      params: [],
//      body:
//       ...instructions

fn allocTree(allocator: mem.Allocator, tree: Node) !*const Node {
    const ptr = try allocator.create(Node);
    ptr.* = tree;
    return ptr;
}

test "constant: 42" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try ast_mod.parseExpr(&arena, "1 + 2 * 3 + 3");
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    // 1 + 2 * 3  parses as  1 + (2 * 3) + 3
    try testing.expectEqualStrings(
        \\%0 = constant(1)
        \\%1 = constant(2)
        \\%2 = constant(3)
        \\%3 = mul(%1, %2)
        \\%4 = add(%0, %3)
        \\%5 = constant(3)
        \\%6 = add(%4, %5)
        \\
    , result);
}

test "variables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try ast_mod.parseExpr(&arena, "const x = 42;");
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = constant(42)
        \\%1 = decl("x", %0)
        \\
    , result);
}

test "var with math" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try ast_mod.parseExpr(&arena, "const x = 42 + 3;");
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = constant(42)
        \\%1 = constant(3)
        \\%2 = add(%0, %1)
        \\%3 = decl("x", %2)
        \\
    , result);
}

test "return identifier ref" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const str =
        \\ const hello = 10;
        \\ return hello;
    ;
    const tree = try ast_mod.parseExpr(&arena, str);
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = constant(10)
        \\%1 = decl("hello", %0)
        \\%2 = decl_ref("hello")
        \\%3 = ret(%2)
        \\
    , result);
}

test "decl ref + math" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const str =
        \\ x * 2 + y
    ;
    const tree = try ast_mod.parseExpr(&arena, str);
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = decl_ref("x")
        \\%1 = constant(2)
        \\%2 = mul(%0, %1)
        \\%3 = decl_ref("y")
        \\%4 = add(%2, %3)
        \\
    , result);
}

test "decl ref + math 2 " {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const str =
        \\const x  = 5;
        \\const y  = x * 2;
    ;
    const tree = try ast_mod.parseExpr(&arena, str);
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = constant(5)
        \\%1 = decl("x", %0)
        \\%2 = decl_ref("x")
        \\%3 = constant(2)
        \\%4 = mul(%2, %3)
        \\%5 = decl("y", %4)
        \\
    , result);
}

test "fn parameters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const str = "fn square(x: i32) { return x * x; }";
    const tree = try ast_mod.parseExpr(&arena, str);
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = param_ref(0)
        \\%1 = param_ref(0)
        \\%2 = mul(%0, %1)
        \\%3 = ret(%2)
        \\
    , result);
}

test "fn 2 parameters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const str = "fn square(a: i32, b: i32) { return  b - a; }";
    const tree = try ast_mod.parseExpr(&arena, str);
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = param_ref(1)
        \\%1 = param_ref(0)
        \\%2 = sub(%0, %1)
        \\%3 = ret(%2)
        \\
    , result);
}

test "fn 2 parameters + locals" {
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
    const tree_ptr = try allocTree(allocator, tree);

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree_ptr);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = param_ref(0)
        \\%1 = constant(1)
        \\%2 = add(%0, %1)
        \\%3 = decl("result", %2)
        \\%4 = decl_ref("result")
        \\%5 = ret(%4)
        \\
    , result);
}

test "parse program" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\fn calc(n: i32) {
        \\  const result = n + 1;
        \\  return result;
        \\}
        \\
        \\fn calc2(n: i32) i32 {
        \\  const result = n;
        \\  return result;
        \\}
    ;

    const tree = try ast_mod.parseExpr(&arena, input);
    const tree_ptr = try allocTree(allocator, tree);

    var program = try generateProgram(allocator, tree_ptr);
    const result = try program.toString(allocator);

    try testing.expectEqualStrings(
        \\function "calc":
        \\  params: [("n", i32)]
        \\  return_type: ?
        \\  body:
        \\    %0 = param_ref(0)
        \\    %1 = constant(1)
        \\    %2 = add(%0, %1)
        \\    %3 = decl("result", %2)
        \\    %4 = decl_ref("result")
        \\    %5 = ret(%4)
        \\
        \\function "calc2":
        \\  params: [("n", i32)]
        \\  return_type: i32
        \\  body:
        \\    %0 = param_ref(0)
        \\    %1 = decl("result", %0)
        \\    %2 = decl_ref("result")
        \\    %3 = ret(%2)
        \\
    , result);
}
