//! ZIR (Zig Intermediate Representation) - Simplified
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

/// ZIR instruction index
pub const Index = u32;

/// ZIR instruction
pub const Inst = union(enum) {
    // ==================== Constants ====================

    /// Integer constant
    int: i64,

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
    current_fn_params: []const ast_mod.Param,

    pub fn init(allocator: Allocator) Generator {
        return .{
            .instructions = .empty,
            .allocator = allocator,
            .block_id = 0,
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
            .expr_stmt => |expr_s| {
                _ = try self.genExpr(expr_s.expr);
            },
            else => {},
        }
    }

    fn genExpr(self: *Generator, node: *Node) !Index {
        switch (node.*) {
            .int_literal => |val| return self.emit(.{ .int = val }),
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
                });
            },
            .unary => |un| {
                const operand = try self.genExpr(un.operand);
                return switch (un.op) {
                    .neg => self.emit(.{ .neg = operand }),
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
            .bool => |v| try writer.print("bool({any})", .{v}),
            .add => |op| try writer.print("add(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .sub => |op| try writer.print("sub(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .mul => |op| try writer.print("mul(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .div => |op| try writer.print("div(%{d}, %{d})", .{ op.lhs, op.rhs }),
            .neg => |idx| try writer.print("neg(%{d})", .{idx}),
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
            .call => |c| try writer.print("call(\"{s}\", {d} args)", .{ c.callee, c.args.len }),
        }
    }
};

fn typeExprToString(t: TypeExpr) []const u8 {
    return switch (t) {
        .primitive => |p| @tagName(p),
        .named => |n| n,
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
