//! AIR (Analyzed Intermediate Representation)
//!
//! AIR is the fully typed IR produced by semantic analysis.
//! All references are resolved, all types are known.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// AIR instruction index
pub const Index = u32;

/// Type representation (fully resolved)
pub const Type = union(enum) {
    /// Integer type: i8, i16, i32, i64, u8, etc.
    int: struct {
        bits: u8, // 8, 16, 32, 64
        signed: bool,
    },

    /// Float type: f32, f64
    float: struct {
        bits: u8, // 32, 64
    },

    /// Boolean type
    bool,

    /// Void type
    void,

    /// Function type
    function: struct {
        params: []const Type,
        return_type: *const Type,
    },

    pub fn format(
        self: Type,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |i| {
                const prefix: u8 = if (i.signed) 'i' else 'u';
                try writer.print("{c}{d}", .{ prefix, i.bits });
            },
            .float => |f| try writer.print("f{d}", .{f.bits}),
            .bool => try writer.writeAll("bool"),
            .void => try writer.writeAll("void"),
            .function => try writer.writeAll("fn"),
        }
    }

    pub fn eql(a: Type, b: Type) bool {
        return switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| ai.bits == bi.bits and ai.signed == bi.signed,
                else => false,
            },
            .float => |af| switch (b) {
                .float => |bf| af.bits == bf.bits,
                else => false,
            },
            .bool => b == .bool,
            .void => b == .void,
            .function => false, // TODO: compare function types
        };
    }
};

/// AIR instruction
pub const Inst = union(enum) {
    // ==================== Constants ====================

    /// Integer constant with type
    const_int: struct {
        value: i64,
        type_: Type,
    },

    /// Float constant with type
    const_float: struct {
        value: f64,
        type_: Type,
    },

    /// Boolean constant
    const_bool: bool,

    // ==================== Arithmetic (typed) ====================

    /// %result: T = %lhs + %rhs
    add: BinOp,

    /// %result: T = %lhs - %rhs
    sub: BinOp,

    /// %result: T = %lhs * %rhs
    mul: BinOp,

    /// %result: T = %lhs / %rhs
    div: BinOp,

    /// %result: T = -%operand
    neg: struct {
        operand: Index,
        type_: Type,
    },

    // ==================== Comparison ====================

    /// %result: bool = %lhs == %rhs
    cmp_eq: CmpOp,

    /// %result: bool = %lhs != %rhs
    cmp_neq: CmpOp,

    /// %result: bool = %lhs < %rhs
    cmp_lt: CmpOp,

    /// %result: bool = %lhs <= %rhs
    cmp_lte: CmpOp,

    /// %result: bool = %lhs > %rhs
    cmp_gt: CmpOp,

    /// %result: bool = %lhs >= %rhs
    cmp_gte: CmpOp,

    // ==================== Memory ====================

    /// Load from local variable
    load: struct {
        local_idx: Index,
        type_: Type,
    },

    /// Store to local variable
    store: struct {
        local_idx: Index,
        value: Index,
    },

    /// Parameter reference
    param: struct {
        idx: u32,
        type_: Type,
    },

    // ==================== Declarations ====================

    /// const name: T = value
    decl_const: struct {
        name: []const u8,
        value: Index,
        type_: Type,
    },

    /// var name: T = value
    decl_var: struct {
        name: []const u8,
        value: ?Index,
        type_: Type,
    },

    /// Function declaration
    decl_fn: struct {
        name: []const u8,
        params: []const Type,
        return_type: Type,
        body_start: Index,
        body_end: Index,
    },

    // ==================== Control flow ====================

    /// Block start
    block_start: u32,

    /// Block end
    block_end: u32,

    /// return value
    ret: struct {
        value: ?Index,
        type_: Type,
    },

    /// Conditional branch
    cond_br: struct {
        cond: Index,
        then_block: u32,
        else_block: ?u32,
    },

    /// Loop start
    loop_start: u32,

    /// Loop end
    loop_end: u32,

    /// Break
    loop_break: u32,

    /// Continue
    loop_continue: u32,

    // ==================== Calls ====================

    /// Function call
    call: struct {
        callee: []const u8,
        args: []const Index,
        return_type: Type,
    },

    pub const BinOp = struct {
        lhs: Index,
        rhs: Index,
        type_: Type,
    };

    pub const CmpOp = struct {
        lhs: Index,
        rhs: Index,
    };
};

/// Dump AIR for debugging
pub fn dump(air: []const Inst, writer: anytype) !void {
    try writer.writeAll("=== AIR ===\n");
    for (air, 0..) |inst, i| {
        try writer.print("%{d} = ", .{i});
        try dumpInst(inst, writer);
        try writer.writeAll("\n");
    }
}

fn dumpInst(inst: Inst, writer: anytype) !void {
    switch (inst) {
        .const_int => |c| try writer.print("const_int({d}: {any})", .{ c.value, c.type_ }),
        .const_float => |c| try writer.print("const_float({d}: {any})", .{ c.value, c.type_ }),
        .const_bool => |b| try writer.print("const_bool({any})", .{b}),
        .add => |op| try writer.print("add(%{d}, %{d}): {any}", .{ op.lhs, op.rhs, op.type_ }),
        .sub => |op| try writer.print("sub(%{d}, %{d}): {any}", .{ op.lhs, op.rhs, op.type_ }),
        .mul => |op| try writer.print("mul(%{d}, %{d}): {any}", .{ op.lhs, op.rhs, op.type_ }),
        .div => |op| try writer.print("div(%{d}, %{d}): {any}", .{ op.lhs, op.rhs, op.type_ }),
        .neg => |n| try writer.print("neg(%{d}): {any}", .{ n.operand, n.type_ }),
        .cmp_eq => |op| try writer.print("cmp_eq(%{d}, %{d})", .{ op.lhs, op.rhs }),
        .cmp_neq => |op| try writer.print("cmp_neq(%{d}, %{d})", .{ op.lhs, op.rhs }),
        .cmp_lt => |op| try writer.print("cmp_lt(%{d}, %{d})", .{ op.lhs, op.rhs }),
        .cmp_lte => |op| try writer.print("cmp_lte(%{d}, %{d})", .{ op.lhs, op.rhs }),
        .cmp_gt => |op| try writer.print("cmp_gt(%{d}, %{d})", .{ op.lhs, op.rhs }),
        .cmp_gte => |op| try writer.print("cmp_gte(%{d}, %{d})", .{ op.lhs, op.rhs }),
        .load => |l| try writer.print("load(%{d}): {any}", .{ l.local_idx, l.type_ }),
        .store => |s| try writer.print("store(%{d}, %{d})", .{ s.local_idx, s.value }),
        .param => |p| try writer.print("param({d}): {any}", .{ p.idx, p.type_ }),
        .decl_const => |d| try writer.print("decl_const(\"{s}\", %{d}): {any}", .{ d.name, d.value, d.type_ }),
        .decl_var => |d| try writer.print("decl_var(\"{s}\"): {any}", .{ d.name, d.type_ }),
        .decl_fn => |f| try writer.print("decl_fn(\"{s}\"): {any}", .{ f.name, f.return_type }),
        .block_start => |id| try writer.print("block_start({d})", .{id}),
        .block_end => |id| try writer.print("block_end({d})", .{id}),
        .ret => |r| {
            if (r.value) |v| {
                try writer.print("ret(%{d}): {any}", .{ v, r.type_ });
            } else {
                try writer.writeAll("ret(void)");
            }
        },
        .cond_br => |br| try writer.print("cond_br(%{d}, then={d})", .{ br.cond, br.then_block }),
        .loop_start => |id| try writer.print("loop_start({d})", .{id}),
        .loop_end => |id| try writer.print("loop_end({d})", .{id}),
        .loop_break => |id| try writer.print("loop_break({d})", .{id}),
        .loop_continue => |id| try writer.print("loop_continue({d})", .{id}),
        .call => |c| try writer.print("call(\"{s}\", {d} args): {any}", .{ c.callee, c.args.len, c.return_type }),
    }
}

// ============================================================================
// Tests
// ============================================================================

test "type equality" {
    const i32_type = Type{ .int = .{ .bits = 32, .signed = true } };
    const i32_type2 = Type{ .int = .{ .bits = 32, .signed = true } };
    const u32_type = Type{ .int = .{ .bits = 32, .signed = false } };

    try std.testing.expect(i32_type.eql(i32_type2));
    try std.testing.expect(!i32_type.eql(u32_type));
}
