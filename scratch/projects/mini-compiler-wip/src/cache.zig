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

// ============================================================================
// File Hash Cache (per-file content hash with mtime)
// ============================================================================

pub const FileHashCache = struct {
    allocator: mem.Allocator,
    entries: std.StringHashMapUnmanaged(FileHashEntry),
    dirty: bool,

    pub const FileHashEntry = struct {
        mtime: i128,
        hash: u64,
        imports: []const []const u8,
    };

    pub fn init(allocator: mem.Allocator) FileHashCache {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .dirty = false,
        };
    }

    pub fn deinit(self: *FileHashCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.imports) |imp| {
                self.allocator.free(imp);
            }
            self.allocator.free(entry.value_ptr.imports);
        }
        self.entries.deinit(self.allocator);
    }

    /// Get or compute hash and imports for a file (uses mtime cache)
    fn ensureCached(self: *FileHashCache, path: []const u8) !*const FileHashEntry {
        const current_mtime = try getFileMtime(path);

        // Check if cached and mtime matches
        if (self.entries.getPtr(path)) |entry| {
            if (entry.mtime == current_mtime) {
                return entry;
            }
            // Mtime changed - free old imports and update
            for (entry.imports) |imp| {
                self.allocator.free(imp);
            }
            self.allocator.free(entry.imports);

            // Read file and update entry
            const source = try readFileSimple(path, self.allocator);
            defer self.allocator.free(source);

            entry.mtime = current_mtime;
            entry.hash = hashSource(source);
            entry.imports = try extractImportPathsSimple(self.allocator, source);
            self.dirty = true;
            return entry;
        }

        // New entry - read file
        const source = try readFileSimple(path, self.allocator);
        defer self.allocator.free(source);

        const key = try self.allocator.dupe(u8, path);
        const imports = try extractImportPathsSimple(self.allocator, source);

        try self.entries.put(self.allocator, key, .{
            .mtime = current_mtime,
            .hash = hashSource(source),
            .imports = imports,
        });

        self.dirty = true;
        return self.entries.getPtr(key).?;
    }

    /// Get hash for file, using cache if mtime unchanged
    pub fn getHash(self: *FileHashCache, path: []const u8) !u64 {
        const entry = try self.ensureCached(path);
        return entry.hash;
    }

    /// Get imports for a file (uses mtime cache)
    pub fn getImports(self: *FileHashCache, allocator: mem.Allocator, path: []const u8) ![]const []const u8 {
        const entry = try self.ensureCached(path);
        // Return a copy since caller expects to own the memory
        const result = try allocator.alloc([]const u8, entry.imports.len);
        for (entry.imports, 0..) |imp, i| {
            result[i] = try allocator.dupe(u8, imp);
        }
        return result;
    }

    /// Load hash cache from disk (binary format for speed)
    pub fn load(self: *FileHashCache, cache_dir: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/file_hashes.bin", .{cache_dir});
        defer self.allocator.free(path);

        const file = fs.cwd().openFile(path, .{}) catch return;
        defer file.close();

        // Read number of entries
        var count_buf: [8]u8 = undefined;
        _ = file.read(&count_buf) catch return;
        const count = mem.readInt(u64, &count_buf, .little);

        // Read each entry
        var i: u64 = 0;
        while (i < count) : (i += 1) {
            // Read path length and path
            var len_buf: [4]u8 = undefined;
            _ = file.read(&len_buf) catch return;
            const path_len = mem.readInt(u32, &len_buf, .little);

            const entry_path = try self.allocator.alloc(u8, path_len);
            _ = file.read(entry_path) catch {
                self.allocator.free(entry_path);
                return;
            };

            // Read mtime and hash
            var mtime_buf: [16]u8 = undefined;
            _ = file.read(&mtime_buf) catch {
                self.allocator.free(entry_path);
                return;
            };
            const mtime = mem.readInt(i128, &mtime_buf, .little);

            var hash_buf: [8]u8 = undefined;
            _ = file.read(&hash_buf) catch {
                self.allocator.free(entry_path);
                return;
            };
            const hash = mem.readInt(u64, &hash_buf, .little);

            // Read imports count and imports
            _ = file.read(&len_buf) catch {
                self.allocator.free(entry_path);
                return;
            };
            const imports_count = mem.readInt(u32, &len_buf, .little);

            const imports = try self.allocator.alloc([]const u8, imports_count);
            var j: u32 = 0;
            while (j < imports_count) : (j += 1) {
                _ = file.read(&len_buf) catch {
                    // Cleanup on error
                    for (imports[0..j]) |imp| self.allocator.free(imp);
                    self.allocator.free(imports);
                    self.allocator.free(entry_path);
                    return;
                };
                const imp_len = mem.readInt(u32, &len_buf, .little);
                const imp = try self.allocator.alloc(u8, imp_len);
                _ = file.read(imp) catch {
                    self.allocator.free(imp);
                    for (imports[0..j]) |im| self.allocator.free(im);
                    self.allocator.free(imports);
                    self.allocator.free(entry_path);
                    return;
                };
                imports[j] = imp;
            }

            try self.entries.put(self.allocator, entry_path, .{
                .mtime = mtime,
                .hash = hash,
                .imports = imports,
            });
        }
    }

    /// Save hash cache to disk (binary format for speed)
    pub fn save(self: *FileHashCache, cache_dir: []const u8) !void {
        if (!self.dirty and self.entries.count() > 0) return; // No changes

        fs.cwd().makePath(cache_dir) catch {};

        const path = try std.fmt.allocPrint(self.allocator, "{s}/file_hashes.bin", .{cache_dir});
        defer self.allocator.free(path);

        const file = try fs.cwd().createFile(path, .{});
        defer file.close();

        // Write number of entries
        var count_buf: [8]u8 = undefined;
        mem.writeInt(u64, &count_buf, self.entries.count(), .little);
        try file.writeAll(&count_buf);

        // Write each entry
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            // Write path
            var len_buf: [4]u8 = undefined;
            mem.writeInt(u32, &len_buf, @intCast(entry.key_ptr.len), .little);
            try file.writeAll(&len_buf);
            try file.writeAll(entry.key_ptr.*);

            // Write mtime and hash
            var mtime_buf: [16]u8 = undefined;
            mem.writeInt(i128, &mtime_buf, entry.value_ptr.mtime, .little);
            try file.writeAll(&mtime_buf);

            var hash_buf: [8]u8 = undefined;
            mem.writeInt(u64, &hash_buf, entry.value_ptr.hash, .little);
            try file.writeAll(&hash_buf);

            // Write imports
            mem.writeInt(u32, &len_buf, @intCast(entry.value_ptr.imports.len), .little);
            try file.writeAll(&len_buf);
            for (entry.value_ptr.imports) |imp| {
                mem.writeInt(u32, &len_buf, @intCast(imp.len), .little);
                try file.writeAll(&len_buf);
                try file.writeAll(imp);
            }
        }

        self.dirty = false;
    }
};

fn readFileSimple(path: []const u8, allocator: mem.Allocator) ![]const u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    return try file.readToEndAlloc(allocator, stat.size);
}

fn extractImportPathsSimple(allocator: mem.Allocator, source: []const u8) ![]const []const u8 {
    var paths: std.ArrayListUnmanaged([]const u8) = .empty;

    var i: usize = 0;
    while (i < source.len) {
        if (i + 6 < source.len and mem.eql(u8, source[i .. i + 6], "import")) {
            i += 6;
            while (i < source.len and (source[i] == ' ' or source[i] == '\t')) : (i += 1) {}
            if (i < source.len and source[i] == '"') {
                i += 1;
                const start = i;
                while (i < source.len and source[i] != '"') : (i += 1) {}
                if (i < source.len) {
                    const path = try allocator.dupe(u8, source[start..i]);
                    try paths.append(allocator, path);
                }
            }
        }
        i += 1;
    }

    return paths.toOwnedSlice(allocator);
}

/// ZIR Cache - Hash-based storage (like git)
/// Stores file hash -> LLVM IR in objects/zir/xx/xxxxxx...
pub const ZirCache = struct {
    allocator: mem.Allocator,
    cache_dir: []const u8,
    // In-memory index: path -> combined_hash (to check if cache is valid)
    index: std.StringHashMapUnmanaged(u64),
    loaded_count: usize,

    pub fn init(allocator: mem.Allocator) ZirCache {
        return .{
            .allocator = allocator,
            .cache_dir = "",
            .index = .empty,
            .loaded_count = 0,
        };
    }

    pub fn deinit(self: *ZirCache) void {
        var iter = self.index.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.index.deinit(self.allocator);
    }

    /// Check if the cache has an entry with matching combined hash
    pub fn hasMatchingHash(self: *ZirCache, path: []const u8, combined_hash: u64) bool {
        if (self.index.get(path)) |cached_hash| {
            return cached_hash == combined_hash;
        }
        return false;
    }

    /// Get cached LLVM IR for a file by combined hash
    pub fn getLlvmIr(self: *ZirCache, path: []const u8, combined_hash: u64) ?[]const u8 {
        _ = path;
        // Content-addressed: lookup by hash
        return self.getObject(combined_hash);
    }

    fn getObject(self: *ZirCache, hash: u64) ?[]const u8 {
        const object_path = self.getObjectPath(hash) catch return null;
        defer self.allocator.free(object_path);

        const file = fs.cwd().openFile(object_path, .{}) catch return null;
        defer file.close();

        const stat = file.stat() catch return null;
        return file.readToEndAlloc(self.allocator, stat.size) catch null;
    }

    pub fn put(self: *ZirCache, path: []const u8, source_hash: u64, zir_hash: u64, function_names: []const []const u8, llvm_ir: ?[]const u8) !void {
        _ = zir_hash;
        _ = function_names;

        // Update in-memory index
        const key = if (self.index.contains(path))
            self.index.getKey(path).?
        else
            try self.allocator.dupe(u8, path);
        try self.index.put(self.allocator, key, source_hash);

        // Store LLVM IR in hash-based object
        if (llvm_ir) |ir| {
            try self.putObject(source_hash, ir);
        }
    }

    fn putObject(self: *ZirCache, hash: u64, content: []const u8) !void {
        const object_path = try self.getObjectPath(hash);
        defer self.allocator.free(object_path);

        const parent = std.fs.path.dirname(object_path) orelse return;
        fs.cwd().makePath(parent) catch {};

        const file = fs.cwd().createFile(object_path, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => return,
            else => return err,
        };
        defer file.close();
        try file.writeAll(content);
    }

    fn getObjectPath(self: *ZirCache, hash: u64) ![]const u8 {
        var hash_str: [16]u8 = undefined;
        _ = std.fmt.bufPrint(&hash_str, "{x:0>16}", .{hash}) catch unreachable;
        return std.fmt.allocPrint(self.allocator, "{s}/zir/{s}/{s}", .{
            self.cache_dir,
            hash_str[0..2],
            hash_str[2..],
        });
    }

    /// Load index from disk (binary format)
    pub fn load(self: *ZirCache, cache_dir: []const u8) !void {
        self.cache_dir = cache_dir;

        const index_path = try std.fmt.allocPrint(self.allocator, "{s}/zir_index.bin", .{cache_dir});
        defer self.allocator.free(index_path);

        const file = fs.cwd().openFile(index_path, .{}) catch return;
        defer file.close();

        // Read count
        var count_buf: [8]u8 = undefined;
        _ = file.read(&count_buf) catch return;
        const count = mem.readInt(u64, &count_buf, .little);

        var i: u64 = 0;
        while (i < count) : (i += 1) {
            // Read path length and path
            var len_buf: [4]u8 = undefined;
            _ = file.read(&len_buf) catch return;
            const path_len = mem.readInt(u32, &len_buf, .little);

            const path = try self.allocator.alloc(u8, path_len);
            _ = file.read(path) catch {
                self.allocator.free(path);
                return;
            };

            // Read hash
            var hash_buf: [8]u8 = undefined;
            _ = file.read(&hash_buf) catch {
                self.allocator.free(path);
                return;
            };
            const hash = mem.readInt(u64, &hash_buf, .little);

            try self.index.put(self.allocator, path, hash);
            self.loaded_count += 1;
        }
    }

    /// Save index to disk (binary format)
    pub fn save(self: *ZirCache, cache_dir: []const u8) !void {
        self.cache_dir = cache_dir;
        fs.cwd().makePath(cache_dir) catch {};

        const index_path = try std.fmt.allocPrint(self.allocator, "{s}/zir_index.bin", .{cache_dir});
        defer self.allocator.free(index_path);

        const file = try fs.cwd().createFile(index_path, .{});
        defer file.close();

        // Write count
        var count_buf: [8]u8 = undefined;
        mem.writeInt(u64, &count_buf, self.index.count(), .little);
        try file.writeAll(&count_buf);

        // Write entries
        var iter = self.index.iterator();
        while (iter.next()) |entry| {
            var len_buf: [4]u8 = undefined;
            mem.writeInt(u32, &len_buf, @intCast(entry.key_ptr.len), .little);
            try file.writeAll(&len_buf);
            try file.writeAll(entry.key_ptr.*);

            var hash_buf: [8]u8 = undefined;
            mem.writeInt(u64, &hash_buf, entry.value_ptr.*, .little);
            try file.writeAll(&hash_buf);
        }
    }
};

// ============================================================================
// AIR Cache (per-function) - Git-style hash-based storage
// ============================================================================

pub const AirCache = struct {
    allocator: mem.Allocator,
    cache_dir: []const u8,
    objects_dir: []const u8,
    // In-memory index: function_key -> zir_hash (for quick lookup)
    index: std.StringHashMapUnmanaged(u64),
    loaded_count: usize,

    pub fn init(allocator: mem.Allocator, cache_dir: []const u8) AirCache {
        const objects_dir = std.fmt.allocPrint(allocator, "{s}/objects", .{cache_dir}) catch cache_dir;
        return .{
            .allocator = allocator,
            .cache_dir = cache_dir,
            .objects_dir = objects_dir,
            .index = .empty,
            .loaded_count = 0,
        };
    }

    pub fn deinit(self: *AirCache) void {
        var iter = self.index.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.index.deinit(self.allocator);
        if (!mem.eql(u8, self.objects_dir, self.cache_dir)) {
            self.allocator.free(self.objects_dir);
        }
    }

    /// Get cached LLVM IR by looking up the hash-based object file
    pub fn get(self: *AirCache, file_path: []const u8, func_name: []const u8, zir_hash: u64) ?[]const u8 {
        _ = file_path;
        _ = func_name;
        // Content-addressed: use zir_hash directly to find the object
        return self.getObject(zir_hash);
    }

    /// Get object by hash (content-addressed lookup)
    fn getObject(self: *AirCache, hash: u64) ?[]const u8 {
        const object_path = self.getObjectPath(hash) catch return null;
        defer self.allocator.free(object_path);

        const file = fs.cwd().openFile(object_path, .{}) catch return null;
        defer file.close();

        const stat = file.stat() catch return null;
        return file.readToEndAlloc(self.allocator, stat.size) catch null;
    }

    /// Store LLVM IR in a hash-based object file
    pub fn put(self: *AirCache, file_path: []const u8, func_name: []const u8, zir_hash: u64, air_hash: u64, llvm_ir: []const u8) !void {
        _ = air_hash;

        // Update in-memory index
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ file_path, func_name });
        if (self.index.contains(key)) {
            self.allocator.free(key);
        } else {
            try self.index.put(self.allocator, key, zir_hash);
        }

        // Write object file (content-addressed by zir_hash)
        try self.putObject(zir_hash, llvm_ir);
    }

    /// Write object to hash-based path
    fn putObject(self: *AirCache, hash: u64, content: []const u8) !void {
        const object_path = try self.getObjectPath(hash);
        defer self.allocator.free(object_path);

        // Ensure parent directory exists (e.g., objects/ab/)
        const parent = std.fs.path.dirname(object_path) orelse return;
        fs.cwd().makePath(parent) catch {};

        // Write object file
        const file = fs.cwd().createFile(object_path, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => return, // Already cached
            else => return err,
        };
        defer file.close();
        try file.writeAll(content);
    }

    /// Get object path: objects/ab/cdef1234... (like git)
    fn getObjectPath(self: *AirCache, hash: u64) ![]const u8 {
        var hash_str: [16]u8 = undefined;
        _ = std.fmt.bufPrint(&hash_str, "{x:0>16}", .{hash}) catch unreachable;
        return std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{
            self.objects_dir,
            hash_str[0..2],
            hash_str[2..],
        });
    }

    pub fn getFunctionCount(self: *AirCache) usize {
        // Count objects in the objects directory
        return self.loaded_count;
    }

    /// Load index from disk (just count objects, don't load content)
    pub fn load(self: *AirCache) !void {
        // Create objects dir if needed
        fs.cwd().makePath(self.objects_dir) catch {};

        // Count existing objects by walking the directory
        var count: usize = 0;
        var dir = fs.cwd().openDir(self.objects_dir, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory and entry.name.len == 2) {
                var subdir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                defer subdir.close();
                var sub_iter = subdir.iterate();
                while (try sub_iter.next()) |_| {
                    count += 1;
                }
            }
        }
        self.loaded_count = count;
    }

    /// Save is now a no-op - objects are written immediately
    pub fn save(self: *AirCache) !void {
        _ = self;
        // Objects are written on put(), nothing to do here
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
    hash_cache: FileHashCache, // Per-file hash cache with mtime

    pub fn init(allocator: mem.Allocator, cache_dir: []const u8) MultiLevelCache {
        return .{
            .allocator = allocator,
            .cache_dir = cache_dir,
            .zir_cache = ZirCache.init(allocator),
            .air_cache = AirCache.init(allocator, cache_dir),
            .file_cache = Cache.init(allocator, cache_dir),
            .hash_cache = FileHashCache.init(allocator),
        };
    }

    /// Load all caches from disk
    pub fn load(self: *MultiLevelCache) !void {
        try self.file_cache.load();
        try self.air_cache.load();
        try self.zir_cache.load(self.cache_dir);
        try self.hash_cache.load(self.cache_dir);
    }

    /// Save all caches to disk
    pub fn save(self: *MultiLevelCache) !void {
        try self.file_cache.save();
        try self.air_cache.save();
        try self.zir_cache.save(self.cache_dir);
        try self.hash_cache.save(self.cache_dir);
    }

    pub fn deinit(self: *MultiLevelCache) void {
        self.zir_cache.deinit();
        self.air_cache.deinit();
        self.file_cache.deinit();
        self.hash_cache.deinit();
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
    verbosity: u8,

    pub const Stats = struct {
        functions_total: usize = 0,
        functions_cached: usize = 0,
        functions_compiled: usize = 0,
    };

    pub fn init(allocator: mem.Allocator, air_cache: *AirCache, file_path: []const u8, verbosity: u8) CachedCodegen {
        return .{
            .allocator = allocator,
            .air_cache = air_cache,
            .file_path = file_path,
            .stats = .{},
            .verbosity = verbosity,
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
                if (self.verbosity >= 2) {
                    std.debug.print("[func] {s}: HIT (hash={x:0>16})\n", .{ function.name, zir_hash });
                }
                try output.appendSlice(self.allocator, cached_ir);
            } else {
                // Cache miss - generate and cache
                self.stats.functions_compiled += 1;
                if (self.verbosity >= 2) {
                    std.debug.print("[func] {s}: MISS (hash={x:0>16}) -> compiling\n", .{ function.name, zir_hash });
                }

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

    const test_ir = "define i32 @main() { ret i32 42 }";

    // Put an entry with LLVM IR
    try cache.put("test.mini", 12345, 67890, &.{ "main", "helper" }, test_ir);

    // Get with matching hash
    const entry = cache.get("test.mini", 12345);
    try testing.expect(entry != null);
    try testing.expectEqual(@as(u64, 12345), entry.?.source_hash);
    try testing.expectEqual(@as(u64, 67890), entry.?.zir_hash);
    try testing.expectEqual(@as(usize, 2), entry.?.function_names.len);
    try testing.expectEqualStrings(test_ir, entry.?.llvm_ir.?);

    // getLlvmIr should return cached IR
    const ir = cache.getLlvmIr("test.mini", 12345);
    try testing.expect(ir != null);
    try testing.expectEqualStrings(test_ir, ir.?);

    // Get with non-matching hash should return null
    const miss = cache.get("test.mini", 99999);
    try testing.expect(miss == null);

    // getLlvmIr with non-matching hash should return null
    const ir_miss = cache.getLlvmIr("test.mini", 99999);
    try testing.expect(ir_miss == null);
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
