const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const json = std.json;

const zir_mod = @import("zir.zig");
const codegen_mod = @import("codegen.zig");

// ============================================================================
// Hash Utilities
// ============================================================================

/// Hash a source file's content
pub fn hashSource(source: []const u8) u64 {
    return std.hash.Wyhash.hash(0, source);
}

/// Hash a function's ZIR instructions for cache invalidation
pub fn hashFunctionZir(function: zir_mod.Function) u64 {
    var hasher = std.hash.Wyhash.init(0);

    // Hash function name
    hasher.update(function.name);

    // Hash parameter types
    for (function.params) |param| {
        hasher.update(param.name);
        hasher.update(&[_]u8{@intFromEnum(param.type)});
    }

    // Hash return type
    if (function.return_type) |rt| {
        hasher.update(&[_]u8{@intFromEnum(rt)});
    }

    // Hash each instruction
    for (function.instructions()) |inst| {
        hasher.update(&[_]u8{@intFromEnum(inst)});
        switch (inst) {
            .literal => |lit| {
                switch (lit.value) {
                    .int => |v| hasher.update(mem.asBytes(&v)),
                    .float => |v| hasher.update(mem.asBytes(&v)),
                    .boolean => |v| hasher.update(&[_]u8{if (v) 1 else 0}),
                }
            },
            .add => |op| {
                hasher.update(mem.asBytes(&op.lhs));
                hasher.update(mem.asBytes(&op.rhs));
            },
            .sub => |op| {
                hasher.update(mem.asBytes(&op.lhs));
                hasher.update(mem.asBytes(&op.rhs));
            },
            .mul => |op| {
                hasher.update(mem.asBytes(&op.lhs));
                hasher.update(mem.asBytes(&op.rhs));
            },
            .div => |op| {
                hasher.update(mem.asBytes(&op.lhs));
                hasher.update(mem.asBytes(&op.rhs));
            },
            .decl => |d| {
                hasher.update(d.name);
                hasher.update(mem.asBytes(&d.value));
            },
            .decl_ref => |d| hasher.update(d.name),
            .return_stmt => |r| hasher.update(mem.asBytes(&r.value)),
            .param_ref => |p| hasher.update(mem.asBytes(&p.value)),
            .call => |c| {
                hasher.update(c.name);
                for (c.args) |arg| {
                    hasher.update(mem.asBytes(&arg));
                }
            },
        }
    }

    return hasher.final();
}

// ============================================================================
// ZIR Cache (per-file)
// ============================================================================

pub const ZirCache = struct {
    allocator: mem.Allocator,
    entries: std.StringHashMapUnmanaged(ZirCacheEntry),

    pub const ZirCacheEntry = struct {
        path: []const u8,
        source_hash: u64,
        zir_hash: u64,
        function_names: []const []const u8,
    };

    pub fn init(allocator: mem.Allocator) ZirCache {
        return .{
            .allocator = allocator,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *ZirCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.path);
            for (entry.value_ptr.function_names) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(entry.value_ptr.function_names);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn get(self: *ZirCache, path: []const u8, source_hash: u64) ?*const ZirCacheEntry {
        if (self.entries.getPtr(path)) |entry| {
            if (entry.source_hash == source_hash) {
                return entry;
            }
        }
        return null;
    }

    pub fn put(self: *ZirCache, path: []const u8, source_hash: u64, zir_hash: u64, function_names: []const []const u8) !void {
        // Free old entry if exists
        if (self.entries.getPtr(path)) |old| {
            for (old.function_names) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(old.function_names);
        }

        const path_copy = if (self.entries.contains(path))
            self.entries.get(path).?.path
        else
            try self.allocator.dupe(u8, path);

        const names_copy = try self.allocator.alloc([]const u8, function_names.len);
        for (function_names, 0..) |name, i| {
            names_copy[i] = try self.allocator.dupe(u8, name);
        }

        try self.entries.put(self.allocator, path_copy, .{
            .path = path_copy,
            .source_hash = source_hash,
            .zir_hash = zir_hash,
            .function_names = names_copy,
        });
    }
};

// ============================================================================
// AIR Cache (per-function)
// ============================================================================

pub const AirCache = struct {
    allocator: mem.Allocator,
    entries: std.StringHashMapUnmanaged(AirCacheEntry),
    cache_dir: []const u8,

    pub const AirCacheEntry = struct {
        function_key: []const u8, // "file:function_name"
        zir_hash: u64, // Hash of the function's ZIR
        air_hash: u64, // Hash of the generated AIR
        llvm_ir: []const u8, // Cached LLVM IR for this function
    };

    pub fn init(allocator: mem.Allocator, cache_dir: []const u8) AirCache {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .cache_dir = cache_dir,
        };
    }

    pub fn deinit(self: *AirCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.function_key);
            self.allocator.free(entry.value_ptr.llvm_ir);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn get(self: *AirCache, file_path: []const u8, func_name: []const u8, zir_hash: u64) ?[]const u8 {
        const key = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ file_path, func_name }) catch return null;
        defer self.allocator.free(key);

        if (self.entries.get(key)) |entry| {
            if (entry.zir_hash == zir_hash) {
                return entry.llvm_ir;
            }
        }
        return null;
    }

    pub fn put(self: *AirCache, file_path: []const u8, func_name: []const u8, zir_hash: u64, air_hash: u64, llvm_ir: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ file_path, func_name });

        // Check if entry exists and update in-place
        if (self.entries.getPtr(key)) |old| {
            // Free the new key we just allocated (we'll reuse the old one)
            self.allocator.free(key);
            // Free old llvm_ir
            self.allocator.free(old.llvm_ir);
            // Update in place
            old.zir_hash = zir_hash;
            old.air_hash = air_hash;
            old.llvm_ir = try self.allocator.dupe(u8, llvm_ir);
            return;
        }

        const ir_copy = try self.allocator.dupe(u8, llvm_ir);

        try self.entries.put(self.allocator, key, .{
            .function_key = key,
            .zir_hash = zir_hash,
            .air_hash = air_hash,
            .llvm_ir = ir_copy,
        });
    }

    pub fn getFunctionCount(self: *AirCache) usize {
        return self.entries.count();
    }

    /// Load AIR cache from disk
    pub fn load(self: *AirCache) !void {
        const manifest_path = try std.fmt.allocPrint(self.allocator, "{s}/air_cache.json", .{self.cache_dir});
        defer self.allocator.free(manifest_path);

        const file = fs.cwd().openFile(manifest_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        const stat = try file.stat();
        const content = try file.readToEndAlloc(self.allocator, stat.size);
        defer self.allocator.free(content);

        try self.parseManifest(content);
    }

    /// Save AIR cache to disk
    pub fn save(self: *AirCache) !void {
        fs.cwd().makePath(self.cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const manifest_path = try std.fmt.allocPrint(self.allocator, "{s}/air_cache.json", .{self.cache_dir});
        defer self.allocator.free(manifest_path);

        const file = try fs.cwd().createFile(manifest_path, .{});
        defer file.close();

        try self.writeManifest(file);
    }

    fn parseManifest(self: *AirCache, content: []const u8) !void {
        const parsed = try json.parseFromSlice(json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;
        const functions = root.get("functions") orelse return;

        for (functions.array.items) |item| {
            const obj = item.object;
            const key = obj.get("key").?.string;
            const zir_hash_val = obj.get("zir_hash").?;
            const zir_hash: u64 = switch (zir_hash_val) {
                .integer => |i| @intCast(i),
                .number_string => |s| std.fmt.parseInt(u64, s, 10) catch 0,
                else => 0,
            };
            const llvm_ir = obj.get("llvm_ir").?.string;

            const key_copy = try self.allocator.dupe(u8, key);
            const ir_copy = try self.allocator.dupe(u8, llvm_ir);

            try self.entries.put(self.allocator, key_copy, .{
                .function_key = key_copy,
                .zir_hash = zir_hash,
                .air_hash = 0,
                .llvm_ir = ir_copy,
            });
        }
    }

    fn writeManifest(self: *AirCache, file: fs.File) !void {
        var content: std.ArrayListUnmanaged(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "{\n  \"functions\": [\n");

        var first = true;
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (!first) try content.appendSlice(self.allocator, ",\n");
            first = false;

            // Escape the LLVM IR for JSON
            var escaped_ir: std.ArrayListUnmanaged(u8) = .empty;
            defer escaped_ir.deinit(self.allocator);
            for (entry.value_ptr.llvm_ir) |c| {
                switch (c) {
                    '\n' => try escaped_ir.appendSlice(self.allocator, "\\n"),
                    '\r' => try escaped_ir.appendSlice(self.allocator, "\\r"),
                    '\t' => try escaped_ir.appendSlice(self.allocator, "\\t"),
                    '"' => try escaped_ir.appendSlice(self.allocator, "\\\""),
                    '\\' => try escaped_ir.appendSlice(self.allocator, "\\\\"),
                    else => try escaped_ir.append(self.allocator, c),
                }
            }

            const entry_str = try std.fmt.allocPrint(self.allocator,
                \\    {{
                \\      "key": "{s}",
                \\      "zir_hash": {d},
                \\      "llvm_ir": "{s}"
                \\    }}
            , .{ entry.value_ptr.function_key, entry.value_ptr.zir_hash, escaped_ir.items });
            defer self.allocator.free(entry_str);
            try content.appendSlice(self.allocator, entry_str);
        }

        try content.appendSlice(self.allocator, "\n  ]\n}\n");
        try file.writeAll(content.items);
    }
};

// ============================================================================
// Multi-Level Cache
// ============================================================================

pub const MultiLevelCache = struct {
    allocator: mem.Allocator,
    cache_dir: []const u8,
    zir_cache: ZirCache,
    air_cache: AirCache,
    file_cache: Cache, // Original file-level cache

    pub fn init(allocator: mem.Allocator, cache_dir: []const u8) MultiLevelCache {
        return .{
            .allocator = allocator,
            .cache_dir = cache_dir,
            .zir_cache = ZirCache.init(allocator),
            .air_cache = AirCache.init(allocator, cache_dir),
            .file_cache = Cache.init(allocator, cache_dir),
        };
    }

    /// Load all caches from disk
    pub fn load(self: *MultiLevelCache) !void {
        try self.file_cache.load();
        try self.air_cache.load();
    }

    /// Save all caches to disk
    pub fn save(self: *MultiLevelCache) !void {
        try self.file_cache.save();
        try self.air_cache.save();
    }

    pub fn deinit(self: *MultiLevelCache) void {
        self.zir_cache.deinit();
        self.air_cache.deinit();
        self.file_cache.deinit();
    }

    pub fn getStats(self: *MultiLevelCache) CacheStats {
        return .{
            .zir_entries = self.zir_cache.entries.count(),
            .air_entries = self.air_cache.entries.count(),
            .file_entries = self.file_cache.entries.count(),
        };
    }

    pub const CacheStats = struct {
        zir_entries: usize,
        air_entries: usize,
        file_entries: usize,
    };
};

// ============================================================================
// Cached Codegen (per-function caching)
// ============================================================================

pub const CachedCodegen = struct {
    allocator: mem.Allocator,
    air_cache: *AirCache,
    file_path: []const u8,
    stats: Stats,

    pub const Stats = struct {
        functions_total: usize = 0,
        functions_cached: usize = 0,
        functions_compiled: usize = 0,
    };

    pub fn init(allocator: mem.Allocator, air_cache: *AirCache, file_path: []const u8) CachedCodegen {
        return .{
            .allocator = allocator,
            .air_cache = air_cache,
            .file_path = file_path,
            .stats = .{},
        };
    }

    /// Generate LLVM IR for a program, using per-function cache
    pub fn generate(self: *CachedCodegen, program: zir_mod.Program) ![]const u8 {
        var output: std.ArrayListUnmanaged(u8) = .empty;

        const functions = program.functions();
        for (functions, 0..) |function, i| {
            self.stats.functions_total += 1;

            // Compute function's ZIR hash
            const zir_hash = hashFunctionZir(function);

            // Check cache
            if (self.air_cache.get(self.file_path, function.name, zir_hash)) |cached_ir| {
                // Cache hit - use cached LLVM IR
                self.stats.functions_cached += 1;
                try output.appendSlice(self.allocator, cached_ir);
            } else {
                // Cache miss - generate and cache
                self.stats.functions_compiled += 1;

                var gen = codegen_mod.init(self.allocator);
                const func_ir = try gen.generateSingleFunction(function);

                // Cache the result
                try self.air_cache.put(self.file_path, function.name, zir_hash, 0, func_ir);

                try output.appendSlice(self.allocator, func_ir);
                self.allocator.free(func_ir);
            }

            if (i < functions.len - 1) {
                try output.appendSlice(self.allocator, "\n");
            }
        }

        return output.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Original File Cache (for backwards compatibility)
// ============================================================================

pub const Cache = struct {
    allocator: mem.Allocator,
    cache_dir: []const u8,
    entries: std.StringHashMapUnmanaged(CacheEntry),

    pub const CacheEntry = struct {
        path: []const u8,
        mtime: i128,
        compiled_at: i128, // Time when cache entry was created
        hash: u64,
        llvm_ir: ?[]const u8,
        dependencies: []const []const u8,
        dirty: bool,
    };

    pub fn init(allocator: mem.Allocator, cache_dir: []const u8) Cache {
        return .{
            .allocator = allocator,
            .cache_dir = cache_dir,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *Cache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            // Free path
            self.allocator.free(entry.value_ptr.path);
            // Free LLVM IR if present
            if (entry.value_ptr.llvm_ir) |ir| {
                self.allocator.free(ir);
            }
            // Free dependencies
            for (entry.value_ptr.dependencies) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(entry.value_ptr.dependencies);
        }
        self.entries.deinit(self.allocator);
    }

    /// Load cache from disk
    pub fn load(self: *Cache) !void {
        const manifest_path = try std.fmt.allocPrint(self.allocator, "{s}/manifest.json", .{self.cache_dir});
        defer self.allocator.free(manifest_path);

        const file = fs.cwd().openFile(manifest_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return, // No cache yet
            else => return err,
        };
        defer file.close();

        const stat = try file.stat();
        const content = try file.readToEndAlloc(self.allocator, stat.size);
        defer self.allocator.free(content);

        try self.parseManifest(content);
    }

    /// Save cache to disk
    pub fn save(self: *Cache) !void {
        // Ensure cache directory exists
        fs.cwd().makePath(self.cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const manifest_path = try std.fmt.allocPrint(self.allocator, "{s}/manifest.json", .{self.cache_dir});
        defer self.allocator.free(manifest_path);

        const file = try fs.cwd().createFile(manifest_path, .{});
        defer file.close();

        try self.writeManifest(file);
    }

    /// Check if a file needs recompilation
    pub fn needsRecompile(self: *Cache, path: []const u8) !bool {
        const entry = self.entries.get(path) orelse return true;

        // Check if file has been modified
        const current_mtime = try getFileMtime(path);
        if (current_mtime != entry.mtime) {
            return true;
        }

        // Check if any dependencies have changed since we last compiled
        for (entry.dependencies) |dep| {
            // Get dependency's current mtime
            const dep_mtime = getFileMtime(dep) catch return true;
            // If dependency was modified after we compiled this file, recompile
            if (dep_mtime > entry.compiled_at) {
                return true;
            }
        }

        return false;
    }

    /// Update cache entry for a file
    pub fn update(
        self: *Cache,
        path: []const u8,
        llvm_ir: []const u8,
        dependencies: []const []const u8,
    ) !void {
        const mtime = try getFileMtime(path);
        const compiled_at = std.time.nanoTimestamp();
        const hash = std.hash.Wyhash.hash(0, llvm_ir);

        // Copy data to cache allocator
        const ir_copy = try self.allocator.dupe(u8, llvm_ir);
        const deps_copy = try self.allocator.alloc([]const u8, dependencies.len);
        for (dependencies, 0..) |dep, i| {
            deps_copy[i] = try self.allocator.dupe(u8, dep);
        }

        // Check if entry exists and free old data
        if (self.entries.getPtr(path)) |old_entry| {
            // Free old data (but not path - we reuse it as key)
            if (old_entry.llvm_ir) |ir| {
                self.allocator.free(ir);
            }
            for (old_entry.dependencies) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(old_entry.dependencies);

            // Update in place
            old_entry.mtime = mtime;
            old_entry.compiled_at = compiled_at;
            old_entry.hash = hash;
            old_entry.llvm_ir = ir_copy;
            old_entry.dependencies = deps_copy;
            old_entry.dirty = false;
        } else {
            // New entry
            const path_copy = try self.allocator.dupe(u8, path);
            try self.entries.put(self.allocator, path_copy, .{
                .path = path_copy,
                .mtime = mtime,
                .compiled_at = compiled_at,
                .hash = hash,
                .llvm_ir = ir_copy,
                .dependencies = deps_copy,
                .dirty = false,
            });
        }

        // Also save LLVM IR to cache file
        try self.saveLLVMIR(path, llvm_ir);
    }

    /// Get cached LLVM IR for a file
    pub fn getCachedLLVMIR(self: *Cache, path: []const u8) ?[]const u8 {
        const entry = self.entries.get(path) orelse return null;
        return entry.llvm_ir;
    }

    /// Mark all entries that depend on a file as dirty
    pub fn invalidateDependents(self: *Cache, changed_path: []const u8) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.dependencies) |dep| {
                if (mem.eql(u8, dep, changed_path)) {
                    entry.value_ptr.dirty = true;
                    // Recursively invalidate
                    self.invalidateDependents(entry.value_ptr.path);
                    break;
                }
            }
        }
    }

    /// Get list of files that need recompilation
    pub fn getDirtyFiles(self: *Cache) ![]const []const u8 {
        var dirty: std.ArrayListUnmanaged([]const u8) = .empty;
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.dirty or try self.needsRecompile(entry.value_ptr.path)) {
                try dirty.append(self.allocator, entry.value_ptr.path);
            }
        }
        return dirty.toOwnedSlice(self.allocator);
    }

    fn saveLLVMIR(self: *Cache, path: []const u8, llvm_ir: []const u8) !void {
        // Ensure cache directory exists
        fs.cwd().makePath(self.cache_dir) catch {};

        // Create cache filename from source path
        const cache_name = try self.getCacheFileName(path);
        defer self.allocator.free(cache_name);

        const cache_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.cache_dir, cache_name });
        defer self.allocator.free(cache_path);

        const file = try fs.cwd().createFile(cache_path, .{});
        defer file.close();
        try file.writeAll(llvm_ir);
    }

    fn getCacheFileName(self: *Cache, path: []const u8) ![]const u8 {
        // Replace / with _ and add .ll extension
        var result = try self.allocator.alloc(u8, path.len + 3);
        for (path, 0..) |c, i| {
            result[i] = if (c == '/') '_' else c;
        }
        @memcpy(result[path.len..], ".ll");
        return result;
    }

    fn parseManifest(self: *Cache, content: []const u8) !void {
        const parsed = try json.parseFromSlice(json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;
        const files = root.get("files") orelse return;

        for (files.array.items) |item| {
            const obj = item.object;
            const path = obj.get("path").?.string;
            const mtime_val = obj.get("mtime").?;
            const mtime: i128 = switch (mtime_val) {
                .integer => |i| i,
                .number_string => |s| std.fmt.parseInt(i128, s, 10) catch 0,
                else => 0,
            };
            const compiled_at_val = obj.get("compiled_at") orelse obj.get("mtime").?;
            const compiled_at: i128 = switch (compiled_at_val) {
                .integer => |i| i,
                .number_string => |s| std.fmt.parseInt(i128, s, 10) catch 0,
                else => 0,
            };
            const hash_val = obj.get("hash").?;
            const hash: u64 = switch (hash_val) {
                .integer => |i| @intCast(i),
                .number_string => |s| std.fmt.parseInt(u64, s, 10) catch 0,
                else => 0,
            };

            // Load dependencies
            var deps: std.ArrayListUnmanaged([]const u8) = .empty;
            if (obj.get("dependencies")) |deps_val| {
                for (deps_val.array.items) |dep| {
                    try deps.append(self.allocator, try self.allocator.dupe(u8, dep.string));
                }
            }

            // Try to load cached LLVM IR
            const llvm_ir = self.loadCachedLLVMIR(path) catch null;

            const path_copy = try self.allocator.dupe(u8, path);
            try self.entries.put(self.allocator, path_copy, .{
                .path = path_copy,
                .mtime = mtime,
                .compiled_at = compiled_at,
                .hash = hash,
                .llvm_ir = llvm_ir,
                .dependencies = try deps.toOwnedSlice(self.allocator),
                .dirty = false,
            });
        }
    }

    fn loadCachedLLVMIR(self: *Cache, path: []const u8) ![]const u8 {
        const cache_name = try self.getCacheFileName(path);
        defer self.allocator.free(cache_name);

        const cache_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.cache_dir, cache_name });
        defer self.allocator.free(cache_path);

        const file = try fs.cwd().openFile(cache_path, .{});
        defer file.close();

        const stat = try file.stat();
        return try file.readToEndAlloc(self.allocator, stat.size);
    }

    fn writeManifest(self: *Cache, file: fs.File) !void {
        // Build JSON string in memory first
        var content: std.ArrayListUnmanaged(u8) = .empty;
        defer content.deinit(self.allocator);

        try content.appendSlice(self.allocator, "{\n  \"files\": [\n");

        var first = true;
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (!first) try content.appendSlice(self.allocator, ",\n");
            first = false;

            const entry_str = try std.fmt.allocPrint(self.allocator,
                \\    {{
                \\      "path": "{s}",
                \\      "mtime": {d},
                \\      "compiled_at": {d},
                \\      "hash": {d},
                \\      "dependencies": [
            , .{ entry.value_ptr.path, entry.value_ptr.mtime, entry.value_ptr.compiled_at, entry.value_ptr.hash });
            defer self.allocator.free(entry_str);
            try content.appendSlice(self.allocator, entry_str);

            for (entry.value_ptr.dependencies, 0..) |dep, i| {
                if (i > 0) try content.appendSlice(self.allocator, ", ");
                const dep_str = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{dep});
                defer self.allocator.free(dep_str);
                try content.appendSlice(self.allocator, dep_str);
            }

            try content.appendSlice(self.allocator, "]\n    }");
        }

        try content.appendSlice(self.allocator, "\n  ]\n}\n");

        // Write to file
        try file.writeAll(content.items);
    }
};

fn getFileMtime(path: []const u8) !i128 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    return stat.mtime;
}

// Incremental compiler that uses the cache
pub const IncrementalCompiler = struct {
    allocator: mem.Allocator,
    cache: Cache,
    verbose: bool,

    pub fn init(allocator: mem.Allocator, cache_dir: []const u8) IncrementalCompiler {
        return .{
            .allocator = allocator,
            .cache = Cache.init(allocator, cache_dir),
            .verbose = false,
        };
    }

    pub fn deinit(self: *IncrementalCompiler) void {
        self.cache.deinit();
    }

    /// Load previous cache state
    pub fn loadCache(self: *IncrementalCompiler) !void {
        try self.cache.load();
    }

    /// Save cache state
    pub fn saveCache(self: *IncrementalCompiler) !void {
        try self.cache.save();
    }

    /// Compile a file, using cache when possible
    pub fn compile(self: *IncrementalCompiler, path: []const u8, compile_fn: *const fn ([]const u8) anyerror![]const u8) !CompileResult {
        const needs_recompile = try self.cache.needsRecompile(path);

        if (!needs_recompile) {
            if (self.cache.getCachedLLVMIR(path)) |cached_ir| {
                if (self.verbose) {
                    std.debug.print("[cache] Using cached: {s}\n", .{path});
                }
                return .{
                    .llvm_ir = cached_ir,
                    .from_cache = true,
                };
            }
        }

        if (self.verbose) {
            std.debug.print("[compile] Compiling: {s}\n", .{path});
        }

        // Compile the file
        const llvm_ir = try compile_fn(path);

        // Update cache
        try self.cache.update(path, llvm_ir, &.{});

        return .{
            .llvm_ir = llvm_ir,
            .from_cache = false,
        };
    }

    pub const CompileResult = struct {
        llvm_ir: []const u8,
        from_cache: bool,
    };
};

// Tests
const testing = std.testing;

test "cache init and basic operations" {
    var cache = Cache.init(testing.allocator, ".mini_cache_test");
    defer cache.deinit();

    // Initially no entries
    try testing.expect(cache.entries.count() == 0);
}

test "cache entry update" {
    var cache = Cache.init(testing.allocator, ".mini_cache_test");
    defer cache.deinit();

    // This would fail without a real file, so we just test the structure
    try testing.expect(cache.getCachedLLVMIR("nonexistent.mini") == null);
}

test "hash source" {
    const source1 = "fn main() { return 42; }";
    const source2 = "fn main() { return 43; }";
    const source1_copy = "fn main() { return 42; }";

    const hash1 = hashSource(source1);
    const hash2 = hashSource(source2);
    const hash1_copy = hashSource(source1_copy);

    // Same content should have same hash
    try testing.expectEqual(hash1, hash1_copy);
    // Different content should have different hash
    try testing.expect(hash1 != hash2);
}

test "zir cache operations" {
    var cache = ZirCache.init(testing.allocator);
    defer cache.deinit();

    // Put an entry
    try cache.put("test.mini", 12345, 67890, &.{ "main", "helper" });

    // Get with matching hash
    const entry = cache.get("test.mini", 12345);
    try testing.expect(entry != null);
    try testing.expectEqual(@as(u64, 12345), entry.?.source_hash);
    try testing.expectEqual(@as(u64, 67890), entry.?.zir_hash);
    try testing.expectEqual(@as(usize, 2), entry.?.function_names.len);

    // Get with non-matching hash should return null
    const miss = cache.get("test.mini", 99999);
    try testing.expect(miss == null);
}

test "air cache operations" {
    var cache = AirCache.init(testing.allocator, ".test_cache");
    defer cache.deinit();

    // Put an entry
    try cache.put("test.mini", "main", 12345, 67890, "define i32 @main() { ret i32 42 }");

    // Get with matching hash
    const ir = cache.get("test.mini", "main", 12345);
    try testing.expect(ir != null);
    try testing.expectEqualStrings("define i32 @main() { ret i32 42 }", ir.?);

    // Get with non-matching hash should return null
    const miss = cache.get("test.mini", "main", 99999);
    try testing.expect(miss == null);

    // Count should be 1
    try testing.expectEqual(@as(usize, 1), cache.getFunctionCount());
}

test "multi-level cache init and stats" {
    var cache = MultiLevelCache.init(testing.allocator, ".test_cache");
    defer cache.deinit();

    const stats = cache.getStats();
    try testing.expectEqual(@as(usize, 0), stats.zir_entries);
    try testing.expectEqual(@as(usize, 0), stats.air_entries);
    try testing.expectEqual(@as(usize, 0), stats.file_entries);
}

test "hash function zir" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ast_mod = @import("ast.zig");

    // Two identical functions should have the same hash
    const tree1 = try ast_mod.parseExpr(&arena, "fn add(a: i32, b: i32) i32 { return a + b; }");
    const program1 = try zir_mod.generateProgram(allocator, &tree1);
    const hash1 = hashFunctionZir(program1.functions()[0]);

    const tree2 = try ast_mod.parseExpr(&arena, "fn add(a: i32, b: i32) i32 { return a + b; }");
    const program2 = try zir_mod.generateProgram(allocator, &tree2);
    const hash2 = hashFunctionZir(program2.functions()[0]);

    try testing.expectEqual(hash1, hash2);

    // Different function body should have different hash
    const tree3 = try ast_mod.parseExpr(&arena, "fn add(a: i32, b: i32) i32 { return a - b; }");
    const program3 = try zir_mod.generateProgram(allocator, &tree3);
    const hash3 = hashFunctionZir(program3.functions()[0]);

    try testing.expect(hash1 != hash3);

    // Different function name should have different hash
    const tree4 = try ast_mod.parseExpr(&arena, "fn sub(a: i32, b: i32) i32 { return a + b; }");
    const program4 = try zir_mod.generateProgram(allocator, &tree4);
    const hash4 = hashFunctionZir(program4.functions()[0]);

    try testing.expect(hash1 != hash4);
}
