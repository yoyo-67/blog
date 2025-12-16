//! LLVM IR Code Generator - Simplified
//!
//! Generates LLVM IR from AIR, similar to how the real Zig compiler
//! can target LLVM for code generation.
//!
//! Output can be compiled with:
//!   llc output.ll -o output.s
//!   clang output.ll -o output

const std = @import("std");
const Allocator = std.mem.Allocator;
const air_mod = @import("air.zig");

pub const Air = air_mod.Inst;
pub const AirIndex = air_mod.Index;
pub const Type = air_mod.Type;

/// Generated LLVM IR
pub const GeneratedIR = struct {
    ll_source: []const u8,

    pub fn deinit(self: *GeneratedIR, allocator: Allocator) void {
        allocator.free(self.ll_source);
    }
};

/// LLVM IR Code Generator
pub const Generator = struct {
    output: std.ArrayListUnmanaged(u8),
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    in_function: bool,
    current_fn_name: []const u8,
    reg_counter: u32,

    // Map AIR indices to LLVM register names
    air_to_reg: std.AutoHashMap(AirIndex, u32),

    pub fn init(allocator: Allocator) Generator {
        return .{
            .output = .empty,
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .in_function = false,
            .current_fn_name = "",
            .reg_counter = 0,
            .air_to_reg = std.AutoHashMap(AirIndex, u32).init(allocator),
        };
    }

    pub fn deinit(self: *Generator) void {
        self.output.deinit(self.allocator);
        self.air_to_reg.deinit();
        self.arena.deinit();
    }

    fn write(self: *Generator, str: []const u8) !void {
        try self.output.appendSlice(self.allocator, str);
    }

    fn print(self: *Generator, comptime fmt: []const u8, args: anytype) !void {
        const writer = self.output.writer(self.allocator);
        try writer.print(fmt, args);
    }

    fn nextReg(self: *Generator) u32 {
        const reg = self.reg_counter;
        self.reg_counter += 1;
        return reg;
    }

    fn mapAirToReg(self: *Generator, air_idx: AirIndex, reg: u32) !void {
        try self.air_to_reg.put(air_idx, reg);
    }

    fn getReg(self: *Generator, air_idx: AirIndex) ?u32 {
        return self.air_to_reg.get(air_idx);
    }

    /// Convert our Type to LLVM IR type string
    fn typeToLLVM(t: Type) []const u8 {
        return switch (t) {
            .int => |i| switch (i.bits) {
                1 => "i1",
                32 => "i32",
                64 => "i64",
                else => "i64",
            },
            .bool => "i1",
            .void => "void",
            .function => "ptr",
        };
    }

    /// Generate LLVM IR from AIR
    pub fn generate(self: *Generator, air: []const Air) !void {
        // LLVM IR header
        try self.write("; ModuleID = 'mini-compiler'\n");
        try self.write("source_filename = \"mini-compiler\"\n");
        try self.write("target triple = \"x86_64-unknown-linux-gnu\"\n\n");

        // Forward declarations
        for (air) |inst| {
            switch (inst) {
                .decl_fn => |f| {
                    try self.write("declare ");
                    try self.write(typeToLLVM(f.return_type));
                    try self.print(" @{s}(", .{f.name});

                    for (f.params, 0..) |param_type, i| {
                        if (i > 0) try self.write(", ");
                        try self.write(typeToLLVM(param_type));
                    }
                    try self.write(")\n");
                },
                else => {},
            }
        }
        try self.write("\n");

        // Generate code for each instruction
        var i: usize = 0;
        while (i < air.len) : (i += 1) {
            try self.genInst(air, @intCast(i));
        }
    }

    fn genInst(self: *Generator, air: []const Air, idx: AirIndex) !void {
        const inst = air[idx];

        switch (inst) {
            .const_int => |c| {
                if (self.in_function) {
                    const reg = self.nextReg();
                    try self.mapAirToReg(idx, reg);
                    _ = c;
                }
            },
            .const_bool => |b| {
                if (self.in_function) {
                    _ = b;
                }
            },
            .add => |op| {
                if (self.in_function) {
                    const reg = self.nextReg();
                    try self.mapAirToReg(idx, reg);

                    const lhs_str = try self.getOperandStr(air, op.lhs);
                    const rhs_str = try self.getOperandStr(air, op.rhs);
                    const type_str = typeToLLVM(op.type_);

                    try self.print("  %{d} = add {s} {s}, {s}\n", .{ reg, type_str, lhs_str, rhs_str });
                }
            },
            .sub => |op| {
                if (self.in_function) {
                    const reg = self.nextReg();
                    try self.mapAirToReg(idx, reg);

                    const lhs_str = try self.getOperandStr(air, op.lhs);
                    const rhs_str = try self.getOperandStr(air, op.rhs);
                    const type_str = typeToLLVM(op.type_);

                    try self.print("  %{d} = sub {s} {s}, {s}\n", .{ reg, type_str, lhs_str, rhs_str });
                }
            },
            .mul => |op| {
                if (self.in_function) {
                    const reg = self.nextReg();
                    try self.mapAirToReg(idx, reg);

                    const lhs_str = try self.getOperandStr(air, op.lhs);
                    const rhs_str = try self.getOperandStr(air, op.rhs);
                    const type_str = typeToLLVM(op.type_);

                    try self.print("  %{d} = mul {s} {s}, {s}\n", .{ reg, type_str, lhs_str, rhs_str });
                }
            },
            .div => |op| {
                if (self.in_function) {
                    const reg = self.nextReg();
                    try self.mapAirToReg(idx, reg);

                    const lhs_str = try self.getOperandStr(air, op.lhs);
                    const rhs_str = try self.getOperandStr(air, op.rhs);
                    const type_str = typeToLLVM(op.type_);

                    try self.print("  %{d} = sdiv {s} {s}, {s}\n", .{ reg, type_str, lhs_str, rhs_str });
                }
            },
            .neg => |n| {
                if (self.in_function) {
                    const reg = self.nextReg();
                    try self.mapAirToReg(idx, reg);

                    const operand_str = try self.getOperandStr(air, n.operand);
                    const type_str = typeToLLVM(n.type_);

                    try self.print("  %{d} = sub {s} 0, {s}\n", .{ reg, type_str, operand_str });
                }
            },
            .load => |l| {
                if (self.in_function) {
                    if (self.getReg(l.local_idx)) |src_reg| {
                        try self.mapAirToReg(idx, src_reg);
                    }
                }
            },
            .param => |p| {
                if (self.in_function) {
                    const reg = self.nextReg();
                    try self.mapAirToReg(idx, reg);

                    try self.print("  %{d} = add {s} %arg{d}, 0\n", .{ reg, typeToLLVM(p.type_), p.idx });
                }
            },
            .decl_const => |d| {
                if (self.in_function) {
                    if (self.getReg(d.value)) |val_reg| {
                        try self.mapAirToReg(idx, val_reg);
                    }
                }
            },
            .decl_var => |d| {
                if (self.in_function) {
                    if (d.value) |v| {
                        if (self.getReg(v)) |val_reg| {
                            try self.mapAirToReg(idx, val_reg);
                        }
                    }
                }
            },
            .decl_fn => |f| {
                try self.write("define ");
                try self.write(typeToLLVM(f.return_type));
                try self.print(" @{s}(", .{f.name});

                for (f.params, 0..) |param_type, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(typeToLLVM(param_type));
                    try self.print(" %arg{d}", .{i});
                }
                try self.write(") {\n");
                try self.write("entry:\n");

                self.in_function = true;
                self.current_fn_name = f.name;
                self.reg_counter = 0;
                self.air_to_reg.clearRetainingCapacity();
            },
            .block_start => {},
            .block_end => {},
            .ret => |r| {
                if (self.in_function) {
                    if (r.value) |v| {
                        const val_str = try self.getOperandStr(air, v);
                        try self.print("  ret {s} {s}\n", .{ typeToLLVM(r.type_), val_str });
                    } else {
                        try self.write("  ret void\n");
                    }

                    try self.write("}\n\n");
                    self.in_function = false;
                }
            },
            .call => |c| {
                if (self.in_function) {
                    const reg = self.nextReg();
                    try self.mapAirToReg(idx, reg);

                    try self.print("  %{d} = call {s} @{s}(", .{ reg, typeToLLVM(c.return_type), c.callee });

                    for (c.args, 0..) |arg, i| {
                        if (i > 0) try self.write(", ");
                        const arg_str = try self.getOperandStr(air, arg);
                        const arg_type = self.getOperandType(air, arg);
                        try self.print("{s} {s}", .{ typeToLLVM(arg_type), arg_str });
                    }
                    try self.write(")\n");
                }
            },
        }
    }

    /// Get the LLVM operand string for an AIR index
    fn getOperandStr(self: *Generator, air: []const Air, air_idx: AirIndex) ![]const u8 {
        const arena_alloc = self.arena.allocator();

        const inst = air[air_idx];
        switch (inst) {
            .const_int => |c| {
                var buf: [32]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "{d}", .{c.value}) catch return "0";
                const result = try arena_alloc.alloc(u8, slice.len);
                @memcpy(result, slice);
                return result;
            },
            .const_bool => |b| {
                return if (b) "1" else "0";
            },
            else => {
                if (self.getReg(air_idx)) |reg| {
                    var buf: [16]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "%{d}", .{reg}) catch return "0";
                    const result = try arena_alloc.alloc(u8, slice.len);
                    @memcpy(result, slice);
                    return result;
                }
                return "0";
            },
        }
    }

    /// Get the type of an AIR operand
    fn getOperandType(self: *Generator, air: []const Air, air_idx: AirIndex) Type {
        _ = self;
        const inst = air[air_idx];
        return switch (inst) {
            .const_int => |c| c.type_,
            .const_bool => Type.bool,
            .add, .sub, .mul, .div => |op| op.type_,
            .neg => |n| n.type_,
            .load => |l| l.type_,
            .param => |p| p.type_,
            .decl_const => |d| d.type_,
            .decl_var => |d| d.type_,
            .call => |c| c.return_type,
            else => Type{ .int = .{ .bits = 64, .signed = true } },
        };
    }

    /// Finalize and return the generated LLVM IR
    pub fn finalize(self: *Generator) !GeneratedIR {
        return .{
            .ll_source = try self.output.toOwnedSlice(self.allocator),
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "generate simple addition" {
    const allocator = std.testing.allocator;

    const air = [_]Air{
        .{ .decl_fn = .{
            .name = "main",
            .params = &.{},
            .return_type = .{ .int = .{ .bits = 32, .signed = true } },
            .body_start = 1,
            .body_end = 4,
        } },
        .{ .const_int = .{ .value = 5, .type_ = .{ .int = .{ .bits = 64, .signed = true } } } },
        .{ .const_int = .{ .value = 3, .type_ = .{ .int = .{ .bits = 64, .signed = true } } } },
        .{ .add = .{ .lhs = 1, .rhs = 2, .type_ = .{ .int = .{ .bits = 64, .signed = true } } } },
        .{ .ret = .{ .value = 3, .type_ = .{ .int = .{ .bits = 32, .signed = true } } } },
    };

    var gen = Generator.init(allocator);
    defer gen.deinit();

    try gen.generate(&air);
    var code = try gen.finalize();
    defer code.deinit(allocator);

    // Should contain LLVM IR
    try std.testing.expect(std.mem.indexOf(u8, code.ll_source, "define i32 @main()") != null);
    try std.testing.expect(std.mem.indexOf(u8, code.ll_source, "add i64") != null);
}
