//! Sema (Semantic Analysis)
//!
//! Takes ZIR and produces AIR by:
//! 1. Resolving references (names → indices)
//! 2. Type checking
//! 3. Type inference

const std = @import("std");
const Allocator = std.mem.Allocator;
const zir_mod = @import("zir.zig");
const air_mod = @import("air.zig");

pub const Zir = zir_mod.Inst;
pub const ZirIndex = zir_mod.Index;
pub const Air = air_mod.Inst;
pub const AirIndex = air_mod.Index;
pub const Type = air_mod.Type;

pub const SemaError = error{
    UndefinedVariable,
    UndefinedFunction,
    TypeMismatch,
    OutOfMemory,
};

/// Symbol in scope
const Symbol = struct {
    name: []const u8,
    type_: Type,
    air_idx: AirIndex, // where the value is in AIR
    is_const: bool,
};

/// Function signature
const FnSig = struct {
    name: []const u8,
    params: []const Type,
    return_type: Type,
    air_idx: AirIndex,
};

/// Semantic Analyzer
pub const Analyzer = struct {
    allocator: Allocator,

    // Symbol tables
    globals: std.StringHashMap(Symbol),
    locals: std.StringHashMap(Symbol),
    functions: std.StringHashMap(FnSig),

    // Current function context
    current_fn: ?[]const u8,
    current_params: []const zir_mod.Inst.FnParam,

    // AIR output
    air: std.ArrayListUnmanaged(Air),

    // ZIR to AIR index mapping
    zir_to_air: std.AutoHashMap(ZirIndex, AirIndex),

    pub fn init(allocator: Allocator) Analyzer {
        return .{
            .allocator = allocator,
            .globals = std.StringHashMap(Symbol).init(allocator),
            .locals = std.StringHashMap(Symbol).init(allocator),
            .functions = std.StringHashMap(FnSig).init(allocator),
            .current_fn = null,
            .current_params = &.{},
            .air = .empty,
            .zir_to_air = std.AutoHashMap(ZirIndex, AirIndex).init(allocator),
        };
    }

    pub fn deinit(self: *Analyzer) void {
        self.globals.deinit();
        self.locals.deinit();
        self.functions.deinit();
        self.air.deinit(self.allocator);
        self.zir_to_air.deinit();
    }

    fn emit(self: *Analyzer, inst: Air) !AirIndex {
        const idx: AirIndex = @intCast(self.air.items.len);
        try self.air.append(self.allocator, inst);
        return idx;
    }

    fn mapZirToAir(self: *Analyzer, zir_idx: ZirIndex, air_idx: AirIndex) !void {
        try self.zir_to_air.put(zir_idx, air_idx);
    }

    fn getAirIdx(self: *Analyzer, zir_idx: ZirIndex) ?AirIndex {
        return self.zir_to_air.get(zir_idx);
    }

    fn lookupVar(self: *Analyzer, name: []const u8) ?Symbol {
        // Check locals first
        if (self.locals.get(name)) |s| return s;
        // Then globals
        if (self.globals.get(name)) |s| return s;
        return null;
    }

    fn typeFromName(name: []const u8) Type {
        if (std.mem.eql(u8, name, "i8")) return Type{ .int = .{ .bits = 8, .signed = true } };
        if (std.mem.eql(u8, name, "i16")) return Type{ .int = .{ .bits = 16, .signed = true } };
        if (std.mem.eql(u8, name, "i32")) return Type{ .int = .{ .bits = 32, .signed = true } };
        if (std.mem.eql(u8, name, "i64")) return Type{ .int = .{ .bits = 64, .signed = true } };
        if (std.mem.eql(u8, name, "u8")) return Type{ .int = .{ .bits = 8, .signed = false } };
        if (std.mem.eql(u8, name, "u16")) return Type{ .int = .{ .bits = 16, .signed = false } };
        if (std.mem.eql(u8, name, "u32")) return Type{ .int = .{ .bits = 32, .signed = false } };
        if (std.mem.eql(u8, name, "u64")) return Type{ .int = .{ .bits = 64, .signed = false } };
        if (std.mem.eql(u8, name, "f32")) return Type{ .float = .{ .bits = 32 } };
        if (std.mem.eql(u8, name, "f64")) return Type{ .float = .{ .bits = 64 } };
        if (std.mem.eql(u8, name, "bool")) return Type.bool;
        if (std.mem.eql(u8, name, "void")) return Type.void;
        return Type{ .int = .{ .bits = 32, .signed = true } }; // default
    }

    /// Analyze ZIR and produce AIR
    pub fn analyze(self: *Analyzer, zir: []const Zir) ![]const Air {
        // First pass: collect function signatures
        for (zir, 0..) |inst, i| {
            switch (inst) {
                .decl_fn => |f| {
                    var param_types: std.ArrayListUnmanaged(Type) = .empty;
                    for (f.params) |p| {
                        try param_types.append(self.allocator, typeFromName(p.type_name));
                    }

                    try self.functions.put(f.name, .{
                        .name = f.name,
                        .params = try param_types.toOwnedSlice(self.allocator),
                        .return_type = typeFromName(f.return_type),
                        .air_idx = @intCast(i),
                    });
                },
                else => {},
            }
        }

        // Second pass: analyze each instruction
        for (zir, 0..) |inst, zir_idx| {
            const air_idx = try self.analyzeInst(inst, @intCast(zir_idx), zir);
            try self.mapZirToAir(@intCast(zir_idx), air_idx);
        }

        return self.air.items;
    }

    fn analyzeInst(self: *Analyzer, inst: Zir, _: ZirIndex, _: []const Zir) !AirIndex {
        switch (inst) {
            .int => |val| {
                return self.emit(.{ .const_int = .{
                    .value = val,
                    .type_ = .{ .int = .{ .bits = 64, .signed = true } },
                } });
            },
            .float => |val| {
                return self.emit(.{ .const_float = .{
                    .value = val,
                    .type_ = .{ .float = .{ .bits = 64 } },
                } });
            },
            .bool => |val| {
                return self.emit(.{ .const_bool = val });
            },
            .add, .sub, .mul, .div => |op| {
                const lhs_air = self.getAirIdx(op.lhs) orelse return SemaError.UndefinedVariable;
                const rhs_air = self.getAirIdx(op.rhs) orelse return SemaError.UndefinedVariable;
                const result_type = Type{ .int = .{ .bits = 64, .signed = true } };

                return self.emit(switch (inst) {
                    .add => .{ .add = .{ .lhs = lhs_air, .rhs = rhs_air, .type_ = result_type } },
                    .sub => .{ .sub = .{ .lhs = lhs_air, .rhs = rhs_air, .type_ = result_type } },
                    .mul => .{ .mul = .{ .lhs = lhs_air, .rhs = rhs_air, .type_ = result_type } },
                    .div => .{ .div = .{ .lhs = lhs_air, .rhs = rhs_air, .type_ = result_type } },
                    else => unreachable,
                });
            },
            .neg => |operand_idx| {
                const operand_air = self.getAirIdx(operand_idx) orelse return SemaError.UndefinedVariable;
                return self.emit(.{ .neg = .{
                    .operand = operand_air,
                    .type_ = .{ .int = .{ .bits = 64, .signed = true } },
                } });
            },
            .cmp_eq, .cmp_neq, .cmp_lt, .cmp_lte, .cmp_gt, .cmp_gte => |op| {
                const lhs_air = self.getAirIdx(op.lhs) orelse return SemaError.UndefinedVariable;
                const rhs_air = self.getAirIdx(op.rhs) orelse return SemaError.UndefinedVariable;

                return self.emit(switch (inst) {
                    .cmp_eq => .{ .cmp_eq = .{ .lhs = lhs_air, .rhs = rhs_air } },
                    .cmp_neq => .{ .cmp_neq = .{ .lhs = lhs_air, .rhs = rhs_air } },
                    .cmp_lt => .{ .cmp_lt = .{ .lhs = lhs_air, .rhs = rhs_air } },
                    .cmp_lte => .{ .cmp_lte = .{ .lhs = lhs_air, .rhs = rhs_air } },
                    .cmp_gt => .{ .cmp_gt = .{ .lhs = lhs_air, .rhs = rhs_air } },
                    .cmp_gte => .{ .cmp_gte = .{ .lhs = lhs_air, .rhs = rhs_air } },
                    else => unreachable,
                });
            },
            .decl_ref => |name| {
                // Look up variable
                if (self.lookupVar(name)) |sym| {
                    return self.emit(.{ .load = .{ .local_idx = sym.air_idx, .type_ = sym.type_ } });
                }
                return SemaError.UndefinedVariable;
            },
            .param_ref => |idx| {
                // Parameter reference - just pass through
                const param_type = if (idx < self.current_params.len)
                    typeFromName(self.current_params[idx].type_name)
                else
                    Type{ .int = .{ .bits = 32, .signed = true } };

                return self.emit(.{ .param = .{
                    .idx = idx,
                    .type_ = param_type,
                } });
            },
            .decl_const => |d| {
                const value_air = self.getAirIdx(d.value) orelse return SemaError.UndefinedVariable;
                const type_ = if (d.type_name) |tn| typeFromName(tn) else Type{ .int = .{ .bits = 64, .signed = true } };

                const air_idx = try self.emit(.{ .decl_const = .{
                    .name = d.name,
                    .value = value_air,
                    .type_ = type_,
                } });

                try self.locals.put(d.name, .{
                    .name = d.name,
                    .type_ = type_,
                    .air_idx = air_idx,
                    .is_const = true,
                });

                return air_idx;
            },
            .decl_var => |d| {
                const value_air = if (d.value) |v| self.getAirIdx(v) else null;
                const type_ = if (d.type_name) |tn| typeFromName(tn) else Type{ .int = .{ .bits = 64, .signed = true } };

                const air_idx = try self.emit(.{ .decl_var = .{
                    .name = d.name,
                    .value = value_air,
                    .type_ = type_,
                } });

                try self.locals.put(d.name, .{
                    .name = d.name,
                    .type_ = type_,
                    .air_idx = air_idx,
                    .is_const = false,
                });

                return air_idx;
            },
            .decl_fn => |f| {
                self.current_fn = f.name;
                self.current_params = f.params;
                self.locals.clearRetainingCapacity();

                // Register parameters as locals
                for (f.params, 0..) |p, i| {
                    try self.locals.put(p.name, .{
                        .name = p.name,
                        .type_ = typeFromName(p.type_name),
                        .air_idx = @intCast(i),
                        .is_const = true,
                    });
                }

                var param_types: std.ArrayListUnmanaged(Type) = .empty;
                for (f.params) |p| {
                    try param_types.append(self.allocator, typeFromName(p.type_name));
                }

                return self.emit(.{ .decl_fn = .{
                    .name = f.name,
                    .params = try param_types.toOwnedSlice(self.allocator),
                    .return_type = typeFromName(f.return_type),
                    .body_start = f.body_start,
                    .body_end = f.body_end,
                } });
            },
            .block_start => |id| return self.emit(.{ .block_start = id }),
            .block_end => |id| return self.emit(.{ .block_end = id }),
            .ret => |v| {
                const value_air = if (v) |idx| self.getAirIdx(idx) else null;
                const ret_type = if (self.current_fn) |fn_name|
                    if (self.functions.get(fn_name)) |sig| sig.return_type else .void
                else
                    .void;

                return self.emit(.{ .ret = .{
                    .value = value_air,
                    .type_ = ret_type,
                } });
            },
            .cond_br => |br| {
                const cond_air = self.getAirIdx(br.cond) orelse return SemaError.UndefinedVariable;
                return self.emit(.{ .cond_br = .{
                    .cond = cond_air,
                    .then_block = br.then_block,
                    .else_block = br.else_block,
                } });
            },
            .loop_start => |id| return self.emit(.{ .loop_start = id }),
            .loop_end => |id| return self.emit(.{ .loop_end = id }),
            .loop_break => |id| return self.emit(.{ .loop_break = id }),
            .loop_continue => |id| return self.emit(.{ .loop_continue = id }),
            .store => |s| {
                const sym = self.lookupVar(s.name) orelse return SemaError.UndefinedVariable;
                const value_air = self.getAirIdx(s.value) orelse return SemaError.UndefinedVariable;

                return self.emit(.{ .store = .{
                    .local_idx = sym.air_idx,
                    .value = value_air,
                } });
            },
            .call => |c| {
                const sig = self.functions.get(c.callee) orelse return SemaError.UndefinedFunction;

                var args: std.ArrayListUnmanaged(AirIndex) = .empty;
                for (c.args) |arg_zir| {
                    const arg_air = self.getAirIdx(arg_zir) orelse return SemaError.UndefinedVariable;
                    try args.append(self.allocator, arg_air);
                }

                return self.emit(.{ .call = .{
                    .callee = c.callee,
                    .args = try args.toOwnedSlice(self.allocator),
                    .return_type = sig.return_type,
                } });
            },
        }
    }

    pub fn getAir(self: *const Analyzer) []const Air {
        return self.air.items;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "sema analyze simple addition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create ZIR manually: 5 + 3
    const zir = [_]Zir{
        .{ .int = 5 },
        .{ .int = 3 },
        .{ .add = .{ .lhs = 0, .rhs = 1 } },
    };

    var analyzer = Analyzer.init(allocator);
    defer analyzer.deinit();

    const air = try analyzer.analyze(&zir);
    try std.testing.expectEqual(@as(usize, 3), air.len);
}
