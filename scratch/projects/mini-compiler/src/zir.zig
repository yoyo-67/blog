//! ZIR (Zig Intermediate Representation)
//!
//! ZIR is produced from the AST before semantic analysis.
//! It's a flat, untyped representation - names are still unresolved strings.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");

pub const Node = ast_mod.Node;
pub const TypeExpr = ast_mod.TypeExpr;
pub const BinaryOp = ast_mod.BinaryOp;
pub const UnaryOp = ast_mod.UnaryOp;
pub const AssignOp = ast_mod.AssignOp;

/// ZIR instruction index
pub const Index = u32;

/// ZIR instruction
pub const Inst = union(enum) {
    // ==================== Constants ====================

    /// Integer constant
    int: i64,

    /// Float constant
    float: f64,

    /// Boolean constant
    bool: bool,

    // ==================== Arithmetic (+ - * /) ====================

    /// %result = %lhs + %rhs
    add: BinOp,

    /// %result = %lhs - %rhs
    sub: BinOp,

    /// %result = %lhs * %rhs
    mul: BinOp,

    /// %result = %lhs / %rhs
    div: BinOp,

    /// %result = -%operand
    neg: Index,

    // ==================== Comparison ====================

    /// %result = %lhs == %rhs
    cmp_eq: BinOp,

    /// %result = %lhs != %rhs
    cmp_neq: BinOp,

    /// %result = %lhs < %rhs
    cmp_lt: BinOp,

    /// %result = %lhs <= %rhs
    cmp_lte: BinOp,

    /// %result = %lhs > %rhs
    cmp_gt: BinOp,

    /// %result = %lhs >= %rhs
    cmp_gte: BinOp,

    // ==================== References (unresolved) ====================

    /// Reference to a declaration by name (unresolved)
    decl_ref: []const u8,

    /// Reference to a parameter by index
    param_ref: u32,

    // ==================== Declarations ====================

    /// const name = %value
    decl_const: struct {
        name: []const u8,
        type_name: ?[]const u8, // unresolved type name
        value: Index,
    },

    /// var name = %value
    decl_var: struct {
        name: []const u8,
        type_name: ?[]const u8,
        value: ?Index,
    },

    /// Function declaration
    decl_fn: struct {
        name: []const u8,
        params: []const FnParam,
        return_type: []const u8,
        body_start: Index,
        body_end: Index,
    },

    // ==================== Control flow ====================

    /// Block marker (start)
    block_start: u32, // block id

    /// Block marker (end)
    block_end: u32, // block id

    /// return %value (or return void)
    ret: ?Index,

    /// Conditional branch: if %cond goto %then_block else %else_block
    cond_br: struct {
        cond: Index,
        then_block: u32,
        else_block: ?u32,
    },

    /// Loop header
    loop_start: u32, // loop id

    /// Loop end
    loop_end: u32, // loop id

    /// Break out of loop
    loop_break: u32, // loop id

    /// Continue to loop start
    loop_continue: u32, // loop id

    // ==================== Store/Load ====================

    /// Store value to variable: name = %value
    store: struct {
        name: []const u8,
        value: Index,
    },

    // ==================== Calls ====================

    /// Function call: %result = name(%args...)
    call: struct {
        callee: []const u8,
        args: []const Index,
    },

    pub const BinOp = struct {
        lhs: Index,
        rhs: Index,
    };

    pub const FnParam = struct {
        name: []const u8,
        type_name: []const u8,
    };
};

/// ZIR Generator - converts AST to ZIR
pub const Generator = struct {
    instructions: std.ArrayListUnmanaged(Inst),
    allocator: Allocator,
    block_id: u32,
    loop_id: u32,
    current_fn_params: []const ast_mod.Param,

    pub fn init(allocator: Allocator) Generator {
        return .{
            .instructions = .empty,
            .allocator = allocator,
            .block_id = 0,
            .loop_id = 0,
            .current_fn_params = &.{},
        };
    }

    pub fn deinit(self: *Generator) void {
        self.instructions.deinit(self.allocator);
    }

    fn emit(self: *Generator, inst: Inst) !Index {
        const idx: Index = @intCast(self.instructions.items.len);
        try self.instructions.append(self.allocator, inst);
        return idx;
    }

    fn nextBlockId(self: *Generator) u32 {
        const id = self.block_id;
        self.block_id += 1;
        return id;
    }

    fn nextLoopId(self: *Generator) u32 {
        const id = self.loop_id;
        self.loop_id += 1;
        return id;
    }

    /// Generate ZIR from AST root
    pub fn generate(self: *Generator, root: *Node) !void {
        if (root.* != .root) return error.ExpectedRoot;

        for (root.root.decls) |decl| {
            try self.genDecl(decl);
        }
    }

    fn genDecl(self: *Generator, node: *Node) !void {
        switch (node.*) {
            .fn_decl => |func| {
                // Save params for lookup
                self.current_fn_params = func.params;

                // Convert params
                var params: std.ArrayListUnmanaged(Inst.FnParam) = .empty;
                for (func.params) |p| {
                    try params.append(self.allocator, .{
                        .name = p.name,
                        .type_name = typeExprToString(p.type_expr),
                    });
                }

                const body_start: Index = @intCast(self.instructions.items.len + 1);

                // Emit function header (placeholder, will update body_end)
                const fn_idx = try self.emit(.{
                    .decl_fn = .{
                        .name = func.name,
                        .params = try params.toOwnedSlice(self.allocator),
                        .return_type = typeExprToString(func.return_type),
                        .body_start = body_start,
                        .body_end = 0, // will update
                    },
                });

                // Generate body
                try self.genStmt(func.body);

                // Update body_end
                self.instructions.items[fn_idx].decl_fn.body_end = @intCast(self.instructions.items.len);

                self.current_fn_params = &.{};
            },
            .const_decl => |decl| {
                const value_idx = try self.genExpr(decl.value);
                _ = try self.emit(.{
                    .decl_const = .{
                        .name = decl.name,
                        .type_name = if (decl.type_expr) |t| typeExprToString(t) else null,
                        .value = value_idx,
                    },
                });
            },
            .var_decl => |decl| {
                const value_idx = if (decl.value) |v| try self.genExpr(v) else null;
                _ = try self.emit(.{
                    .decl_var = .{
                        .name = decl.name,
                        .type_name = if (decl.type_expr) |t| typeExprToString(t) else null,
                        .value = value_idx,
                    },
                });
            },
            else => {},
        }
    }

    fn genStmt(self: *Generator, node: *Node) !void {
        switch (node.*) {
            .block => |blk| {
                const id = self.nextBlockId();
                _ = try self.emit(.{ .block_start = id });
                for (blk.statements) |stmt| {
                    try self.genStmt(stmt);
                }
                _ = try self.emit(.{ .block_end = id });
            },
            .const_decl => |decl| {
                const value_idx = try self.genExpr(decl.value);
                _ = try self.emit(.{
                    .decl_const = .{
                        .name = decl.name,
                        .type_name = if (decl.type_expr) |t| typeExprToString(t) else null,
                        .value = value_idx,
                    },
                });
            },
            .var_decl => |decl| {
                const value_idx = if (decl.value) |v| try self.genExpr(v) else null;
                _ = try self.emit(.{
                    .decl_var = .{
                        .name = decl.name,
                        .type_name = if (decl.type_expr) |t| typeExprToString(t) else null,
                        .value = value_idx,
                    },
                });
            },
            .return_stmt => |ret| {
                const value_idx = if (ret.value) |v| try self.genExpr(v) else null;
                _ = try self.emit(.{ .ret = value_idx });
            },
            .if_stmt => |if_s| {
                const cond_idx = try self.genExpr(if_s.condition);
                const then_id = self.nextBlockId();
                const else_id = if (if_s.else_block != null) self.nextBlockId() else null;

                _ = try self.emit(.{
                    .cond_br = .{
                        .cond = cond_idx,
                        .then_block = then_id,
                        .else_block = else_id,
                    },
                });

                _ = try self.emit(.{ .block_start = then_id });
                try self.genStmt(if_s.then_block);
                _ = try self.emit(.{ .block_end = then_id });

                if (if_s.else_block) |else_blk| {
                    _ = try self.emit(.{ .block_start = else_id.? });
                    try self.genStmt(else_blk);
                    _ = try self.emit(.{ .block_end = else_id.? });
                }
            },
            .while_stmt => |while_s| {
                const loop_id = self.nextLoopId();
                _ = try self.emit(.{ .loop_start = loop_id });

                const cond_idx = try self.genExpr(while_s.condition);
                const body_id = self.nextBlockId();

                _ = try self.emit(.{
                    .cond_br = .{
                        .cond = cond_idx,
                        .then_block = body_id,
                        .else_block = null,
                    },
                });

                _ = try self.emit(.{ .block_start = body_id });
                try self.genStmt(while_s.body);
                _ = try self.emit(.{ .block_end = body_id });

                _ = try self.emit(.{ .loop_end = loop_id });
            },
            .break_stmt => {
                _ = try self.emit(.{ .loop_break = self.loop_id - 1 });
            },
            .continue_stmt => {
                _ = try self.emit(.{ .loop_continue = self.loop_id - 1 });
            },
            .assign_stmt => |assign| {
                // Get target name (must be identifier)
                const name = switch (assign.target.*) {
                    .identifier => |n| n,
                    else => return error.InvalidAssignTarget,
                };

                // Generate value (handle compound assignment)
                const value_idx = switch (assign.op) {
                    .assign => try self.genExpr(assign.value),
                    .add_assign => blk: {
                        const lhs = try self.emit(.{ .decl_ref = name });
                        const rhs = try self.genExpr(assign.value);
                        break :blk try self.emit(.{ .add = .{ .lhs = lhs, .rhs = rhs } });
                    },
                    .sub_assign => blk: {
                        const lhs = try self.emit(.{ .decl_ref = name });
                        const rhs = try self.genExpr(assign.value);
                        break :blk try self.emit(.{ .sub = .{ .lhs = lhs, .rhs = rhs } });
                    },
                    .mul_assign => blk: {
                        const lhs = try self.emit(.{ .decl_ref = name });
                        const rhs = try self.genExpr(assign.value);
                        break :blk try self.emit(.{ .mul = .{ .lhs = lhs, .rhs = rhs } });
                    },
                    .div_assign => blk: {
                        const lhs = try self.emit(.{ .decl_ref = name });
                        const rhs = try self.genExpr(assign.value);
                        break :blk try self.emit(.{ .div = .{ .lhs = lhs, .rhs = rhs } });
                    },
                };

                _ = try self.emit(.{ .store = .{ .name = name, .value = value_idx } });
            },
            .expr_stmt => |expr_s| {
                _ = try self.genExpr(expr_s.expr);
            },
            else => {},
        }
    }

    fn genExpr(self: *Generator, node: *Node) !Index {
        switch (node.*) {
            .int_literal => |val| return self.emit(.{ .int = val }),
            .float_literal => |val| return self.emit(.{ .float = val }),
            .bool_literal => |val| return self.emit(.{ .bool = val }),
            .identifier => |name| {
                // Check if it's a parameter
                for (self.current_fn_params, 0..) |p, i| {
                    if (std.mem.eql(u8, p.name, name)) {
                        return self.emit(.{ .param_ref = @intCast(i) });
                    }
                }
                return self.emit(.{ .decl_ref = name });
            },
            .binary => |bin| {
                const lhs = try self.genExpr(bin.left);
                const rhs = try self.genExpr(bin.right);
                const op = Inst.BinOp{ .lhs = lhs, .rhs = rhs };

                return self.emit(switch (bin.op) {
                    .add => .{ .add = op },
                    .sub => .{ .sub = op },
                    .mul => .{ .mul = op },
                    .div => .{ .div = op },
                    .mod => .{ .div = op }, // simplified
                    .eq => .{ .cmp_eq = op },
                    .neq => .{ .cmp_neq = op },
                    .lt => .{ .cmp_lt = op },
                    .lte => .{ .cmp_lte = op },
                    .gt => .{ .cmp_gt = op },
                    .gte => .{ .cmp_gte = op },
                    .@"and" => .{ .cmp_eq = op }, // simplified
                    .@"or" => .{ .cmp_neq = op }, // simplified
                });
            },
            .unary => |un| {
                const operand = try self.genExpr(un.operand);
                return switch (un.op) {
                    .neg => self.emit(.{ .neg = operand }),
                    .not => self.emit(.{ .neg = operand }), // simplified
                };
            },
            .call => |c| {
                const callee_name = switch (c.callee.*) {
                    .identifier => |n| n,
                    else => return error.InvalidCallee,
                };

                var args: std.ArrayListUnmanaged(Index) = .empty;
                for (c.args) |arg| {
                    try args.append(self.allocator, try self.genExpr(arg));
                }

                return self.emit(.{
                    .call = .{
                        .callee = callee_name,
                        .args = try args.toOwnedSlice(self.allocator),
                    },
                });
            },
            .grouped => |g| return self.genExpr(g.expr),
            else => return error.UnsupportedExpr,
        }
    }

    pub fn getInstructions(self: *const Generator) []const Inst {
        return self.instructions.items;
    }

    /// Dump ZIR for debugging
    pub fn dump(self: *const Generator, writer: anytype) !void {
        try writer.writeAll("=== ZIR ===\n");
        for (self.instructions.items, 0..) |inst, i| {
            try writer.print("%{d} = ", .{i});
            try dumpInst(inst, writer);
            try writer.writeAll("\n");
        }
    }

    fn dumpInst(inst: Inst, writer: anytype) !void {
        switch (inst) {
            .int => |v| try writer.print("int({d})", .{v}),
            .float => |v| try writer.print("float({d})", .{v}),
            .bool => |v| try writer.print("bool({any})", .{v}),
            .add => |op| try writer.print("add(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .sub => |op| try writer.print("sub(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .mul => |op| try writer.print("mul(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .div => |op| try writer.print("div(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .neg => |idx| try writer.print("neg(%{d})", .{idx}),
            .cmp_eq => |op| try writer.print("cmp_eq(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .cmp_lt => |op| try writer.print("cmp_lt(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .cmp_gt => |op| try writer.print("cmp_gt(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .cmp_neq, .cmp_lte, .cmp_gte => try writer.writeAll("cmp_..."),
            .decl_ref => |name| try writer.print("decl_ref(\"{s}\")", .{name}),
            .param_ref => |idx| try writer.print("param_ref({d})", .{idx}),
            .decl_const => |d| try writer.print("decl_const(\"{s}\", %{d})", .{ d.name, d.value }),
            .decl_var => |d| try writer.print("decl_var(\"{s}\")", .{d.name}),
            .decl_fn => |f| try writer.print("decl_fn(\"{s}\")", .{f.name}),
            .block_start => |id| try writer.print("block_start({d})", .{id}),
            .block_end => |id| try writer.print("block_end({d})", .{id}),
            .ret => |v| {
                if (v) |idx| {
                    try writer.print("ret(%{d})", .{idx});
                } else {
                    try writer.writeAll("ret(void)");
                }
            },
            .cond_br => |br| try writer.print("cond_br(%{d}, then={d})", .{ br.cond, br.then_block }),
            .loop_start => |id| try writer.print("loop_start({d})", .{id}),
            .loop_end => |id| try writer.print("loop_end({d})", .{id}),
            .loop_break => |id| try writer.print("loop_break({d})", .{id}),
            .loop_continue => |id| try writer.print("loop_continue({d})", .{id}),
            .store => |s| try writer.print("store(\"{s}\", %{d})", .{ s.name, s.value }),
            .call => |c| try writer.print("call(\"{s}\", {d} args)", .{ c.callee, c.args.len }),
        }
    }
};

fn typeExprToString(t: TypeExpr) []const u8 {
    return switch (t) {
        .primitive => |p| @tagName(p),
        .named => |n| n,
        .pointer, .optional => "ptr",
    };
}

// ============================================================================
// Tests
// ============================================================================

test "zir generate simple function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parser_mod = @import("parser.zig");
    var parser = parser_mod.Parser.init("fn add(a: i32, b: i32) i32 { return a + b; }", allocator);
    const ast = try parser.parse();

    var gen = Generator.init(allocator);
    defer gen.deinit();

    try gen.generate(ast);

    // Should have instructions for: fn_decl, block_start, param_ref, param_ref, add, ret, block_end
    try std.testing.expect(gen.instructions.items.len > 0);
}
