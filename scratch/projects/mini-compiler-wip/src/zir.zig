const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const token_mod = @import("token.zig");
const ast_mod = @import("ast.zig");
const node_mod = @import("node.zig");
const Node = node_mod.Node;

const Zir = @This();

instructions: std.ArrayListUnmanaged(Instruction),
parameters: std.StringHashMapUnmanaged(u32),

fn init() Zir {
    return .{
        .instructions = .empty,
        .parameters = .empty,
    };
}

fn generate(self: *Zir, allocator: mem.Allocator, node: Node) !InstructionRef {
    switch (node) {
        .int_literal => |lit| return try self.emit(allocator, .{ .constant = lit.value }),
        .binary_op => |bin| {
            const lhs = try self.generate(allocator, bin.lhs.*);
            const rhs = try self.generate(allocator, bin.rhs.*);
            return switch (bin.op) {
                .plus => try self.emit(allocator, .{ .add = .{ .lhs = lhs, .rhs = rhs } }),
                .minus => try self.emit(allocator, .{ .sub = .{ .lhs = lhs, .rhs = rhs } }),
                .mul => try self.emit(allocator, .{ .mul = .{ .lhs = lhs, .rhs = rhs } }),
                .div => try self.emit(allocator, .{ .div = .{ .lhs = lhs, .rhs = rhs } }),
            };
        },
        .root => |root| {
            var last: InstructionRef = 0;
            for (root.decls) |decl| {
                last = try self.generate(allocator, decl);
            }
            return last;
        },
        .identifier => |val| {
            const instruction_ref = try self.generate(allocator, val.value.*);
            return try self.emit(allocator, .{ .decl = .{
                .name = val.name,
                .value = instruction_ref,
            } });
        },
        .return_stmt => |val| {
            const instructuion_ref = try self.generate(allocator, val.value.*);
            return try self.emit(allocator, .{ .return_stmt = .{ .value = instructuion_ref } });
        },
        .identifier_ref => |val| {
            if (self.parameters.get(val.name)) |param_idx| {
                return try self.emit(allocator, .{ .param_ref = param_idx });
            }

            return try self.emit(allocator, .{ .decl_ref = val.name });
        },
        .fn_decl => |val| {
            // loop on the parameters and emit them.
            // then emit the decleration on the block
            var last: InstructionRef = 0;
            for (val.params, 0..) |param, idx| {
                try self.parameters.put(allocator, param.name, @intCast(idx));
                // .last = try self.emit(allocator, .{ .param_ref = @intCast(idx) });
            }

            for (val.block.decls) |decl| {
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

const Instruction = union(enum) {
    constant: i32,
    add: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
    },
    sub: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
    },
    mul: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
    },
    div: struct {
        lhs: InstructionRef,
        rhs: InstructionRef,
    },
    decl: struct {
        name: []const u8,
        value: InstructionRef,
    },
    decl_ref: []const u8,
    return_stmt: struct {
        value: InstructionRef,
    },
    param_ref: u32,

    pub fn toString(self: Instruction, idx: usize, writer: anytype) !void {
        try writer.print("%{d} = ", .{idx});
        switch (self) {
            .constant => |val| try writer.print("constant({d})", .{val}),
            .add => |val| try writer.print("add(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .sub => |val| try writer.print("sub(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .mul => |val| try writer.print("mul(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .div => |val| try writer.print("div(%{d}, %{d})", .{ val.lhs, val.rhs }),
            .decl => |val| try writer.print("decl(\"{s}\", %{d})", .{ val.name, val.value }),
            .decl_ref => |val| try writer.print("decl_ref(\"{s}\")", .{val}),
            .return_stmt => |val| try writer.print("ret(%{d})", .{val.value}),
            .param_ref => |val| try writer.print("param_ref({d})", .{val}),
        }
    }
};

fn deinit(self: *Zir, allocator: mem.Allocator) void {
    self.instructions.deinit(allocator);
    self.parameters.deinit(allocator);
}

test "constant: 42" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tree = try ast_mod.parseExpr(&arena, "1 + 2 * 3 + 3");

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

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

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

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

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

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

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

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

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

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

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

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

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

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

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

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

    var zir = Zir.init();
    _ = try zir.generate(allocator, tree);

    const result = try zir.toString(allocator);

    try testing.expectEqualStrings(
        \\%0 = param_ref(0)
        \\%1 = decl("n", %0)
        \\%2 = constant(1)
        \\%3 = add(%1, %2)
        \\%4 = decl("result", %3)
        \\%5 = ret(%4)
        \\
    , result);
}
