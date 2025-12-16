//! Code Generator - Simplified
//!
//! Generates C code from AIR.

const std = @import("std");
const Allocator = std.mem.Allocator;
const air_mod = @import("air.zig");

pub const Air = air_mod.Inst;
pub const AirIndex = air_mod.Index;
pub const Type = air_mod.Type;

/// Generated C code
pub const GeneratedCode = struct {
    c_source: []const u8,

    pub fn deinit(self: *GeneratedCode, allocator: Allocator) void {
        allocator.free(self.c_source);
    }
};

/// Code Generator
pub const Generator = struct {
    output: std.ArrayListUnmanaged(u8),
    allocator: Allocator,
    indent: usize,
    in_function: bool,

    pub fn init(allocator: Allocator) Generator {
        return .{
            .output = .empty,
            .allocator = allocator,
            .indent = 0,
            .in_function = false,
        };
    }

    pub fn deinit(self: *Generator) void {
        self.output.deinit(self.allocator);
    }

    fn write(self: *Generator, str: []const u8) !void {
        try self.output.appendSlice(self.allocator, str);
    }

    fn print(self: *Generator, comptime fmt: []const u8, args: anytype) !void {
        const writer = self.output.writer(self.allocator);
        try writer.print(fmt, args);
    }

    fn writeIndent(self: *Generator) !void {
        for (0..self.indent) |_| {
            try self.write("    ");
        }
    }

    fn typeToCType(t: Type) []const u8 {
        return switch (t) {
            .int => |i| switch (i.bits) {
                32 => if (i.signed) "int32_t" else "uint32_t",
                64 => if (i.signed) "int64_t" else "uint64_t",
                else => "int64_t",
            },
            .bool => "bool",
            .void => "void",
            .function => "void*",
        };
    }

    /// Generate C code from AIR
    pub fn generate(self: *Generator, air: []const Air) !void {
        // Header
        try self.write("#include <stdio.h>\n");
        try self.write("#include <stdint.h>\n");
        try self.write("#include <stdbool.h>\n\n");

        // Forward declarations
        for (air) |inst| {
            switch (inst) {
                .decl_fn => |f| {
                    try self.write(typeToCType(f.return_type));
                    try self.print(" {s}(", .{f.name});

                    for (f.params, 0..) |param_type, i| {
                        if (i > 0) try self.write(", ");
                        try self.write(typeToCType(param_type));
                        try self.print(" p{d}", .{i});
                    }
                    try self.write(");\n");
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
                    try self.writeIndent();
                    try self.write(typeToCType(c.type_));
                    try self.print(" t{d} = {d};\n", .{ idx, c.value });
                }
            },
            .const_bool => |b| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.print("bool t{d} = {s};\n", .{ idx, if (b) "true" else "false" });
                }
            },
            .add => |op| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(op.type_));
                    try self.print(" t{d} = t{d} + t{d};\n", .{ idx, op.lhs, op.rhs });
                }
            },
            .sub => |op| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(op.type_));
                    try self.print(" t{d} = t{d} - t{d};\n", .{ idx, op.lhs, op.rhs });
                }
            },
            .mul => |op| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(op.type_));
                    try self.print(" t{d} = t{d} * t{d};\n", .{ idx, op.lhs, op.rhs });
                }
            },
            .div => |op| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(op.type_));
                    try self.print(" t{d} = t{d} / t{d};\n", .{ idx, op.lhs, op.rhs });
                }
            },
            .neg => |n| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(n.type_));
                    try self.print(" t{d} = -t{d};\n", .{ idx, n.operand });
                }
            },
            .load => |l| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(l.type_));
                    try self.print(" t{d} = t{d};\n", .{ idx, l.local_idx });
                }
            },
            .param => |p| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(p.type_));
                    try self.print(" t{d} = p{d};\n", .{ idx, p.idx });
                }
            },
            .decl_const => |d| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write("const ");
                    try self.write(typeToCType(d.type_));
                    try self.print(" t{d} = t{d}; // {s}\n", .{ idx, d.value, d.name });
                }
            },
            .decl_var => |d| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(d.type_));
                    try self.print(" t{d}", .{idx});
                    if (d.value) |v| {
                        try self.print(" = t{d}", .{v});
                    }
                    try self.print("; // {s}\n", .{d.name});
                }
            },
            .decl_fn => |f| {
                try self.write(typeToCType(f.return_type));
                try self.print(" {s}(", .{f.name});

                for (f.params, 0..) |param_type, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(typeToCType(param_type));
                    try self.print(" p{d}", .{i});
                }
                try self.write(") {\n");
                self.in_function = true;
                self.indent = 1;
            },
            .block_start => {},
            .block_end => {},
            .ret => |r| {
                if (self.in_function) {
                    try self.writeIndent();
                    if (r.value) |v| {
                        try self.print("return t{d};\n", .{v});
                    } else {
                        try self.write("return;\n");
                    }

                    // Close function
                    self.indent = 0;
                    try self.write("}\n\n");
                    self.in_function = false;
                }
            },
            .call => |c| {
                if (self.in_function) {
                    try self.writeIndent();
                    try self.write(typeToCType(c.return_type));
                    try self.print(" t{d} = {s}(", .{ idx, c.callee });

                    for (c.args, 0..) |arg, i| {
                        if (i > 0) try self.write(", ");
                        try self.print("t{d}", .{arg});
                    }
                    try self.write(");\n");
                }
            },
        }
    }

    /// Finalize and return the generated C code
    pub fn finalize(self: *Generator) !GeneratedCode {
        return .{
            .c_source = try self.output.toOwnedSlice(self.allocator),
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

    // Should contain C code
    try std.testing.expect(std.mem.indexOf(u8, code.c_source, "int32_t main()") != null);
}
