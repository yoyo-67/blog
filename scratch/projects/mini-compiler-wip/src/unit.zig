const std = @import("std");
const mem = std.mem;
const fs = std.fs;

const ast_mod = @import("ast.zig");
const zir_mod = @import("zir.zig");
const node_mod = @import("node.zig");
const Node = node_mod.Node;

pub const CompilationUnit = struct {
    path: []const u8,
    source: []const u8,
    tree: Node,
    imports: std.StringHashMapUnmanaged(Import),
    allocator: mem.Allocator,

    pub const Import = struct {
        path: []const u8,
        namespace: []const u8,
        unit: ?*CompilationUnit,
    };

    pub fn init(allocator: mem.Allocator, path: []const u8) CompilationUnit {
        return .{
            .path = path,
            .source = "",
            .tree = undefined,
            .imports = .empty,
            .allocator = allocator,
        };
    }

    pub fn load(self: *CompilationUnit, arena: *std.heap.ArenaAllocator) !void {
        const allocator = arena.allocator();

        // Read source file
        const dir = fs.cwd();
        const file = try dir.openFile(self.path, .{});
        defer file.close();

        const stat = try file.stat();
        self.source = try file.readToEndAlloc(allocator, stat.size);

        // Parse into AST
        self.tree = try ast_mod.parseExpr(arena, self.source);

        // Extract imports
        try self.extractImports(allocator);
    }

    fn extractImports(self: *CompilationUnit, allocator: mem.Allocator) !void {
        for (self.tree.root.decls) |decl| {
            if (decl == .import_decl) {
                const imp = decl.import_decl;
                try self.imports.put(allocator, imp.namespace, .{
                    .path = imp.path,
                    .namespace = imp.namespace,
                    .unit = null,
                });
            }
        }
    }

    pub fn loadImports(self: *CompilationUnit, arena: *std.heap.ArenaAllocator, units: *std.StringHashMapUnmanaged(*CompilationUnit)) !void {
        const allocator = arena.allocator();

        var iter = self.imports.iterator();
        while (iter.next()) |entry| {
            const import_path = entry.value_ptr.path;

            // Check if already loaded
            if (units.get(import_path)) |existing| {
                entry.value_ptr.unit = existing;
                continue;
            }

            // Resolve path relative to current file
            const resolved_path = try resolvePath(allocator, self.path, import_path);

            // Create and load new compilation unit
            const unit = try allocator.create(CompilationUnit);
            unit.* = CompilationUnit.init(allocator, resolved_path);
            try unit.load(arena);

            try units.put(allocator, import_path, unit);
            entry.value_ptr.unit = unit;

            // Recursively load imports
            try unit.loadImports(arena, units);
        }
    }

    pub fn generateProgram(self: *const CompilationUnit, allocator: mem.Allocator) !zir_mod.Program {
        var functions: std.ArrayListUnmanaged(zir_mod.Function) = .empty;

        // Generate functions from this unit
        for (self.tree.root.decls) |*decl| {
            if (decl.* == .fn_decl) {
                const fn_decl = try zir_mod.generateFunction(allocator, decl);
                try functions.append(allocator, fn_decl);
            }
        }

        // Generate functions from imported units with namespace prefix
        var iter = self.imports.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.unit) |unit| {
                for (unit.tree.root.decls) |*decl| {
                    if (decl.* == .fn_decl) {
                        var fn_decl = try zir_mod.generateFunction(allocator, decl);
                        // Prefix function name with namespace
                        const prefixed_name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ entry.value_ptr.namespace, fn_decl.name });
                        fn_decl.name = prefixed_name;
                        try functions.append(allocator, fn_decl);
                    }
                }
            }
        }

        return .{ .functions_list = functions };
    }

    pub fn getImportedNamespaces(self: *const CompilationUnit) []const []const u8 {
        var namespaces: std.ArrayListUnmanaged([]const u8) = .empty;
        var iter = self.imports.iterator();
        while (iter.next()) |entry| {
            namespaces.append(self.allocator, entry.key_ptr.*) catch {};
        }
        return namespaces.items;
    }
};

fn resolvePath(allocator: mem.Allocator, base_path: []const u8, import_path: []const u8) ![]const u8 {
    // Get directory of base file
    if (mem.lastIndexOf(u8, base_path, "/")) |idx| {
        const dir = base_path[0 .. idx + 1];
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ dir, import_path });
    }
    return import_path;
}

// Tests
const testing = std.testing;

test "derive namespace from path" {
    const result = ast_mod.deriveNamespace("math.mini");
    try testing.expectEqualStrings("math", result);
}

test "derive namespace from nested path" {
    const result = ast_mod.deriveNamespace("lib/utils.mini");
    try testing.expectEqualStrings("utils", result);
}
