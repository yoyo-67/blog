const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const posix = std.posix;

const ast_mod = @import("ast.zig");
const zir_mod = @import("zir.zig");
const codegen_mod = @import("codegen.zig");
const unit_mod = @import("unit.zig");
const cache_mod = @import("cache.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (mem.eql(u8, command, "run")) {
        if (args.len < 3) {
            std.debug.print("Error: 'run' requires a file argument\n", .{});
            return;
        }
        try runFile(allocator, args[2]);
    } else if (mem.eql(u8, command, "emit")) {
        if (args.len < 3) {
            std.debug.print("Error: 'emit' requires a file argument\n", .{});
            return;
        }
        try emitLLVM(allocator, args[2]);
    } else if (mem.eql(u8, command, "eval")) {
        if (args.len < 3) {
            std.debug.print("Error: 'eval' requires a code string\n", .{});
            return;
        }
        try evalString(allocator, args[2]);
    } else if (mem.eql(u8, command, "build")) {
        if (args.len < 3) {
            std.debug.print("Error: 'build' requires a file argument\n", .{});
            return;
        }
        const verbosity: u8 = if (args.len > 3)
            if (mem.eql(u8, args[3], "-vv")) 2 else if (mem.eql(u8, args[3], "-v")) 1 else 0
        else
            0;
        try incrementalBuild(allocator, args[2], verbosity);
    } else if (mem.eql(u8, command, "clean")) {
        try cleanCache(allocator);
    } else {
        // Treat as file path for backward compatibility
        try runFile(allocator, command);
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: comp <command> [args]
        \\
        \\Commands:
        \\  run <file>        Compile and run the file
        \\  emit <file>       Emit LLVM IR to stdout
        \\  eval <code>       Compile and run code string
        \\  build <file> [-v] Incremental build
        \\  clean             Clean the build cache
        \\
        \\Verbosity:
        \\  -v   Show cache status and function counts
        \\  -vv  Show detailed hashes, timing, and per-function info
        \\
        \\Examples:
        \\  comp run example.mini
        \\  comp emit example.mini > output.ll
        \\  comp eval "fn main() i32 {{ return 42; }}"
        \\  comp build main.mini -v
        \\  comp build main.mini -vv
        \\
    , .{});
}

fn runFile(allocator: mem.Allocator, path: []const u8) !void {
    const llvm_ir = try compileUnit(allocator, path);
    defer allocator.free(llvm_ir);

    try runLLVM(allocator, llvm_ir);
}

fn emitLLVM(allocator: mem.Allocator, path: []const u8) !void {
    const llvm_ir = try compileUnit(allocator, path);
    defer allocator.free(llvm_ir);

    // Write to stdout
    _ = try posix.write(posix.STDOUT_FILENO, llvm_ir);
}

fn evalString(allocator: mem.Allocator, source: []const u8) !void {
    try compileAndRun(allocator, source);
}

fn readFile(allocator: mem.Allocator, path: []const u8) ![]const u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const contents = try file.readToEndAlloc(allocator, stat.size);
    return contents;
}

fn compile(allocator: mem.Allocator, source: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Parse
    const tree = try ast_mod.parseExpr(&arena, source);

    // Generate ZIR
    const program = try zir_mod.generateProgram(arena_alloc, &tree);

    // Generate LLVM IR
    var gen = codegen_mod.init(allocator);
    const llvm_ir = try gen.generate(program);

    return llvm_ir;
}

fn compileUnit(allocator: mem.Allocator, path: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Create compilation unit
    var unit = unit_mod.CompilationUnit.init(arena_alloc, path);
    try unit.load(&arena);

    // Load all imports
    var units: std.StringHashMapUnmanaged(*unit_mod.CompilationUnit) = .empty;
    try unit.loadImports(&arena, &units);

    // Generate program with all imported functions
    const program = try unit.generateProgram(arena_alloc);

    // Generate LLVM IR
    var gen = codegen_mod.init(allocator);
    const llvm_ir = try gen.generate(program);

    return llvm_ir;
}

fn compileAndRun(allocator: mem.Allocator, source: []const u8) !void {
    const llvm_ir = try compile(allocator, source);
    defer allocator.free(llvm_ir);

    try runLLVM(allocator, llvm_ir);
}

fn runLLVM(allocator: mem.Allocator, llvm_ir: []const u8) !void {
    // Write to temp file
    const tmp_path = "/tmp/mini_output.ll";
    const tmp_file = try fs.cwd().createFile(tmp_path, .{});
    try tmp_file.writeAll(llvm_ir);
    tmp_file.close();

    // Run with docker + lli
    var child = process.Child.init(&.{
        "docker",
        "run",
        "--rm",
        "-v",
        "/tmp:/tmp",
        "silkeh/clang:18",
        "lli",
        tmp_path,
    }, allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const result = try child.spawnAndWait();
    if (result.Exited != 0) {
        std.debug.print("Program exited with code: {d}\n", .{result.Exited});
    }
}

// ============================================================================
// Incremental Compilation with Multi-Level Cache
// ============================================================================

const CACHE_DIR = ".mini_cache";

fn incrementalBuild(allocator: mem.Allocator, path: []const u8, verbosity: u8) !void {
    const start_time = std.time.nanoTimestamp();

    // Initialize multi-level cache
    var multi_cache = cache_mod.MultiLevelCache.init(allocator, CACHE_DIR);
    defer multi_cache.deinit();

    // Load all caches (file cache + AIR cache + ZIR cache)
    try multi_cache.load();

    if (verbosity >= 1) {
        std.debug.print("[cache] Loaded: {d} files (ZIR), {d} functions (AIR)\n", .{
            multi_cache.zir_cache.index.count(),
            multi_cache.air_cache.getFunctionCount(),
        });
    }

    // Compute combined hash of main file + ALL transitive dependencies (using mtime cache)
    const source = try readFile(allocator, path);
    defer allocator.free(source);
    const combined_hash = try computeCombinedHashWithCache(allocator, path, source, &multi_cache.hash_cache);

    if (verbosity >= 2) {
        std.debug.print("[hash] Combined hash of all deps: {x:0>16}\n", .{combined_hash});
    }

    // Check if combined hash matches cached hash
    const needs_recompile = !multi_cache.zir_cache.hasMatchingHash(path, combined_hash);

    if (needs_recompile) {
        // Use per-file incremental compilation
        const result = try incrementalCompilePerFile(allocator, path, &multi_cache, verbosity);
        defer allocator.free(result.llvm_ir);

        // Update caches
        try multi_cache.zir_cache.put(path, combined_hash, 0, &.{}, result.llvm_ir);
        try multi_cache.save();

        if (verbosity >= 1) {
            std.debug.print("[build] Files: {d} cached, {d} compiled\n", .{
                result.files_cached,
                result.files_compiled,
            });
        }

        const end_time = std.time.nanoTimestamp();
        const elapsed_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        std.debug.print("[build] Compiled: {s}\n", .{path});
        if (verbosity >= 2) {
            std.debug.print("[time] Total: {d:.2}ms\n", .{elapsed_ms});
        }

        // Write output
        const output_path = try getOutputPath(allocator, path);
        defer allocator.free(output_path);

        const out_file = try fs.cwd().createFile(output_path, .{});
        defer out_file.close();
        try out_file.writeAll(result.llvm_ir);

        std.debug.print("[build] Output: {s}\n", .{output_path});
    } else {
        if (verbosity >= 1) {
            std.debug.print("[build] No changes, using cache: {s}\n", .{path});
        }

        // Use cached combined output
        if (multi_cache.zir_cache.getLlvmIr(path, combined_hash)) |cached_ir| {
            const output_path = try getOutputPath(allocator, path);
            defer allocator.free(output_path);

            const out_file = try fs.cwd().createFile(output_path, .{});
            defer out_file.close();
            try out_file.writeAll(cached_ir);
            allocator.free(cached_ir);

            std.debug.print("[build] Output (cached): {s}\n", .{output_path});
        } else {
            std.debug.print("[build] Cache miss, recompiling...\n", .{});
            try incrementalBuild(allocator, path, verbosity);
        }
    }
}

const PerFileResult = struct {
    llvm_ir: []const u8,
    files_cached: usize,
    files_compiled: usize,
};

const FILE_MARKER_PREFIX = "; ==== FILE: ";
const FILE_MARKER_SUFFIX = " ====\n";

/// Per-file incremental compilation with surgical patching
/// Uses markers in combined IR to enable fast partial rebuilds
fn incrementalCompilePerFile(
    allocator: mem.Allocator,
    path: []const u8,
    multi_cache: *cache_mod.MultiLevelCache,
    verbosity: u8,
) !PerFileResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Collect all files in dependency tree with their hashes
    var file_hashes: std.StringHashMapUnmanaged(u64) = .empty;
    var file_order: std.ArrayListUnmanaged([]const u8) = .empty;
    try collectAllFileHashes(arena_alloc, path, &multi_cache.hash_cache, &file_hashes, &file_order);

    // Try surgical patch if we have cached combined output
    if (try surgicalPatch(allocator, arena_alloc, path, multi_cache, &file_hashes, &file_order, verbosity)) |result| {
        return result;
    }

    if (verbosity >= 1) {
        std.debug.print("[incremental] Full rebuild: {d} files\n", .{file_order.items.len});
    }

    // Full rebuild - build output with file markers
    var output: std.ArrayListUnmanaged(u8) = .empty;
    var files_compiled: usize = 0;

    for (file_order.items) |file_path| {
        const file_hash = file_hashes.get(file_path).?;

        // Add file marker
        try output.appendSlice(allocator, FILE_MARKER_PREFIX);
        try output.appendSlice(allocator, file_path);
        try output.appendSlice(allocator, ":");
        var hash_buf: [16]u8 = undefined;
        _ = std.fmt.bufPrint(&hash_buf, "{x:0>16}", .{file_hash}) catch unreachable;
        try output.appendSlice(allocator, &hash_buf);
        try output.appendSlice(allocator, FILE_MARKER_SUFFIX);

        // Compile this file
        files_compiled += 1;
        if (verbosity >= 2) {
            std.debug.print("[file] {s}: MISS -> compiling\n", .{file_path});
        }

        const file_ir = try compileOneFile(allocator, file_path, &arena);
        try output.appendSlice(allocator, file_ir);
        allocator.free(file_ir);
    }

    return .{
        .llvm_ir = try output.toOwnedSlice(allocator),
        .files_cached = 0,
        .files_compiled = files_compiled,
    };
}

/// Try to surgically patch the cached combined IR
/// Returns null if full rebuild is needed
fn surgicalPatch(
    allocator: mem.Allocator,
    arena_alloc: mem.Allocator,
    path: []const u8,
    multi_cache: *cache_mod.MultiLevelCache,
    file_hashes: *std.StringHashMapUnmanaged(u64),
    file_order: *std.ArrayListUnmanaged([]const u8),
    verbosity: u8,
) !?PerFileResult {
    // Get cached combined IR (using hash 0 as key for combined output)
    const cached_combined = multi_cache.zir_cache.getCombinedIr(path) orelse return null;
    defer allocator.free(cached_combined);

    // Parse cached IR into sections by file markers
    var cached_sections: std.StringHashMapUnmanaged([]const u8) = .empty;
    var cached_hashes: std.StringHashMapUnmanaged(u64) = .empty;

    var pos: usize = 0;
    while (pos < cached_combined.len) {
        // Find next file marker
        const marker_start = mem.indexOfPos(u8, cached_combined, pos, FILE_MARKER_PREFIX) orelse break;
        const path_start = marker_start + FILE_MARKER_PREFIX.len;

        // Parse "path:hash ===="
        const colon_pos = mem.indexOfPos(u8, cached_combined, path_start, ":") orelse break;
        const file_path = cached_combined[path_start..colon_pos];
        const hash_start = colon_pos + 1;
        const marker_end = mem.indexOfPos(u8, cached_combined, hash_start, FILE_MARKER_SUFFIX) orelse break;
        const hash_str = cached_combined[hash_start..marker_end];

        // Parse hash
        const cached_hash = std.fmt.parseInt(u64, hash_str, 16) catch break;

        // Find end of this section (next marker or end of file)
        const content_start = marker_end + FILE_MARKER_SUFFIX.len;
        const next_marker = mem.indexOfPos(u8, cached_combined, content_start, FILE_MARKER_PREFIX) orelse cached_combined.len;
        const content = cached_combined[content_start..next_marker];

        // Store in maps (using arena since we're just reading)
        const path_copy = try arena_alloc.dupe(u8, file_path);
        try cached_sections.put(arena_alloc, path_copy, content);
        try cached_hashes.put(arena_alloc, path_copy, cached_hash);

        pos = next_marker;
    }

    if (cached_sections.count() == 0) return null; // No valid sections found

    // Check how many files changed
    var changed_files: std.ArrayListUnmanaged([]const u8) = .empty;
    for (file_order.items) |file_path| {
        const new_hash = file_hashes.get(file_path).?;
        const old_hash = cached_hashes.get(file_path) orelse {
            // New file not in cache
            try changed_files.append(arena_alloc, file_path);
            continue;
        };
        if (new_hash != old_hash) {
            try changed_files.append(arena_alloc, file_path);
        }
    }

    // If too many changes or no cached data, do full rebuild
    if (changed_files.items.len > 100 or cached_sections.count() < file_order.items.len / 2) {
        return null;
    }

    if (verbosity >= 1) {
        std.debug.print("[incremental] Surgical patch: {d}/{d} files changed\n", .{ changed_files.items.len, file_order.items.len });
    }

    // Compile only changed files
    var new_sections: std.StringHashMapUnmanaged([]const u8) = .empty;
    var compile_arena = std.heap.ArenaAllocator.init(allocator);
    defer compile_arena.deinit();

    for (changed_files.items) |file_path| {
        if (verbosity >= 2) {
            std.debug.print("[file] {s}: MISS -> compiling\n", .{file_path});
        }
        const file_ir = try compileOneFile(arena_alloc, file_path, &compile_arena);
        try new_sections.put(arena_alloc, file_path, file_ir);
    }

    // Build output with markers, using cached or newly compiled sections
    var output: std.ArrayListUnmanaged(u8) = .empty;
    var files_cached: usize = 0;
    var files_compiled: usize = 0;

    for (file_order.items) |file_path| {
        const file_hash = file_hashes.get(file_path).?;

        // Add file marker
        try output.appendSlice(allocator, FILE_MARKER_PREFIX);
        try output.appendSlice(allocator, file_path);
        try output.appendSlice(allocator, ":");
        var hash_buf: [16]u8 = undefined;
        _ = std.fmt.bufPrint(&hash_buf, "{x:0>16}", .{file_hash}) catch unreachable;
        try output.appendSlice(allocator, &hash_buf);
        try output.appendSlice(allocator, FILE_MARKER_SUFFIX);

        // Use newly compiled or cached section
        if (new_sections.get(file_path)) |new_ir| {
            try output.appendSlice(allocator, new_ir);
            files_compiled += 1;
        } else if (cached_sections.get(file_path)) |cached_ir| {
            try output.appendSlice(allocator, cached_ir);
            files_cached += 1;
            if (verbosity >= 2) {
                std.debug.print("[file] {s}: HIT\n", .{file_path});
            }
        } else {
            // Shouldn't happen, but compile if needed
            const file_ir = try compileOneFile(arena_alloc, file_path, &compile_arena);
            try output.appendSlice(allocator, file_ir);
            files_compiled += 1;
        }
    }

    return .{
        .llvm_ir = try output.toOwnedSlice(allocator),
        .files_cached = files_cached,
        .files_compiled = files_compiled,
    };
}

/// Collect all files in dependency tree with their content hashes
fn collectAllFileHashes(
    allocator: mem.Allocator,
    path: []const u8,
    hash_cache: *cache_mod.FileHashCache,
    file_hashes: *std.StringHashMapUnmanaged(u64),
    file_order: *std.ArrayListUnmanaged([]const u8),
) !void {
    // Check if already visited
    if (file_hashes.contains(path)) return;

    // Get hash for this file
    const hash = try hash_cache.getHash(path);
    const path_copy = try allocator.dupe(u8, path);
    try file_hashes.put(allocator, path_copy, hash);
    try file_order.append(allocator, path_copy);

    // Get imports and recurse
    const imports = try hash_cache.getImports(allocator, path);
    defer {
        for (imports) |imp| allocator.free(imp);
        allocator.free(imports);
    }

    const dir = std.fs.path.dirname(path) orelse "";
    for (imports) |import_path| {
        const resolved = if (dir.len > 0)
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, import_path })
        else
            try allocator.dupe(u8, import_path);
        defer allocator.free(resolved);

        try collectAllFileHashes(allocator, resolved, hash_cache, file_hashes, file_order);
    }
}

/// Compile a single file to LLVM IR
fn compileOneFile(allocator: mem.Allocator, path: []const u8, arena: *std.heap.ArenaAllocator) ![]const u8 {
    const arena_alloc = arena.allocator();

    // Load and parse this single file
    var unit = unit_mod.CompilationUnit.init(arena_alloc, path);
    try unit.load(arena);

    // Generate ZIR for just this file's functions
    var functions: std.ArrayListUnmanaged(zir_mod.Function) = .empty;
    for (unit.tree.root.decls) |*decl| {
        if (decl.* == .fn_decl) {
            const fn_decl = try zir_mod.generateFunction(arena_alloc, decl);
            try functions.append(arena_alloc, fn_decl);
        }
    }

    // Generate LLVM IR
    var gen = codegen_mod.init(allocator);
    var output: std.ArrayListUnmanaged(u8) = .empty;

    for (functions.items) |function| {
        const func_ir = try gen.generateSingleFunction(function);
        try output.appendSlice(allocator, func_ir);
        try output.appendSlice(allocator, "\n");
        allocator.free(func_ir);
    }

    return output.toOwnedSlice(allocator);
}

const CompileCacheResult = struct {
    llvm_ir: []const u8,
    functions_cached: usize,
    functions_compiled: usize,
};

/// Compile a unit using multi-level cache (ZIR per-file, AIR per-function)
fn compileWithCache(
    allocator: mem.Allocator,
    path: []const u8,
    multi_cache: *cache_mod.MultiLevelCache,
    verbosity: u8,
) !CompileCacheResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Read source file
    const source = try readFile(arena_alloc, path);
    const source_hash = cache_mod.hashSource(source);

    // Compute combined hash using mtime cache
    const combined_hash = try computeCombinedHashWithCache(arena_alloc, path, source, &multi_cache.hash_cache);

    if (verbosity >= 2) {
        std.debug.print("[hash] Source: {x:0>16}, Combined: {x:0>16}\n", .{ source_hash, combined_hash });
    }

    // Check file-level LLVM IR cache first - skip all stages if hit
    if (multi_cache.zir_cache.getLlvmIr(path, combined_hash)) |cached_ir| {
        if (verbosity >= 1) {
            std.debug.print("[cache] File-level HIT: {s} (skipping lexer/parser/ZIR/codegen)\n", .{path});
        }
        // Copy to caller's allocator since arena will be freed
        const ir_copy = try allocator.dupe(u8, cached_ir);
        return .{
            .llvm_ir = ir_copy,
            .functions_cached = 0,
            .functions_compiled = 0,
        };
    } else {
        if (verbosity >= 1) {
            std.debug.print("[cache] File-level MISS: {s} (running full pipeline)\n", .{path});
        }
    }

    // Create compilation unit
    var unit = unit_mod.CompilationUnit.init(arena_alloc, path);
    try unit.load(&arena);

    // Load all imports
    var units: std.StringHashMapUnmanaged(*unit_mod.CompilationUnit) = .empty;
    try unit.loadImports(&arena, &units);

    // Generate program with all imported functions
    const program = try unit.generateProgram(arena_alloc);

    if (verbosity >= 2) {
        std.debug.print("[zir] Generated {d} functions\n", .{program.functions().len});
    }

    // Generate LLVM IR using per-function AIR cache
    var cached_gen = cache_mod.CachedCodegen.init(allocator, &multi_cache.air_cache, path, verbosity);
    const llvm_ir = try cached_gen.generate(program);

    // Update ZIR cache with function names and LLVM IR for file-level caching
    var func_names: std.ArrayListUnmanaged([]const u8) = .empty;
    for (program.functions()) |func| {
        try func_names.append(arena_alloc, func.name);
    }
    try multi_cache.zir_cache.put(path, combined_hash, combined_hash, func_names.items, llvm_ir);

    return .{
        .llvm_ir = llvm_ir,
        .functions_cached = cached_gen.stats.functions_cached,
        .functions_compiled = cached_gen.stats.functions_compiled,
    };
}

/// Compute a combined hash using mtime-based file hash cache
fn computeCombinedHashWithCache(allocator: mem.Allocator, path: []const u8, source: []const u8, hash_cache: *cache_mod.FileHashCache) !u64 {
    var hasher = std.hash.Wyhash.init(0);

    // Hash the main source
    hasher.update(source);

    // Recursively hash ALL transitive dependencies using mtime cache
    var visited: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer {
        var iter = visited.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        visited.deinit(allocator);
    }

    try hashTransitiveDepsWithCache(allocator, path, &hasher, &visited, hash_cache);

    return hasher.final();
}

/// Recursively hash all transitive dependencies using mtime cache
fn hashTransitiveDepsWithCache(
    allocator: mem.Allocator,
    path: []const u8,
    hasher: *std.hash.Wyhash,
    visited: *std.StringHashMapUnmanaged([]const u8),
    hash_cache: *cache_mod.FileHashCache,
) !void {
    const dir = std.fs.path.dirname(path) orelse "";

    // Get imports for this file
    const import_paths = hash_cache.getImports(allocator, path) catch return;
    defer {
        for (import_paths) |p| allocator.free(p);
        allocator.free(import_paths);
    }

    for (import_paths) |import_path| {
        const resolved_path = if (dir.len > 0)
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, import_path })
        else
            try allocator.dupe(u8, import_path);

        // Skip if already visited
        if (visited.contains(resolved_path)) {
            allocator.free(resolved_path);
            continue;
        }

        // Store in visited (key owns the memory)
        try visited.put(allocator, resolved_path, resolved_path);

        // Get hash using mtime cache (avoids re-reading unchanged files)
        const dep_hash = hash_cache.getHash(resolved_path) catch continue;
        hasher.update(mem.asBytes(&dep_hash));

        // Recursively process this dependency's imports
        try hashTransitiveDepsWithCache(allocator, resolved_path, hasher, visited, hash_cache);
    }
}

/// Extract import paths from source without full parsing
/// Looks for patterns like: import "path.mini" as name;
fn extractImportPaths(allocator: mem.Allocator, source: []const u8) ![]const []const u8 {
    var paths: std.ArrayListUnmanaged([]const u8) = .empty;

    var i: usize = 0;
    while (i < source.len) {
        // Look for "import" keyword
        if (i + 6 < source.len and mem.eql(u8, source[i .. i + 6], "import")) {
            i += 6;
            // Skip whitespace
            while (i < source.len and (source[i] == ' ' or source[i] == '\t')) : (i += 1) {}
            // Expect opening quote
            if (i < source.len and source[i] == '"') {
                i += 1;
                const start = i;
                // Find closing quote
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

fn collectDependencies(allocator: mem.Allocator, path: []const u8) ![]const []const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Get directory of source file
    const dir = std.fs.path.dirname(path) orelse "";

    // Create compilation unit to get imports
    var unit = unit_mod.CompilationUnit.init(arena_alloc, path);
    unit.load(&arena) catch return &.{};

    var deps: std.ArrayListUnmanaged([]const u8) = .empty;
    var iter = unit.imports.iterator();
    while (iter.next()) |entry| {
        // Build full path for dependency
        const full_path = if (dir.len > 0)
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, entry.value_ptr.path })
        else
            try allocator.dupe(u8, entry.value_ptr.path);
        try deps.append(allocator, full_path);
    }

    return deps.toOwnedSlice(allocator);
}

fn getOutputPath(allocator: mem.Allocator, path: []const u8) ![]const u8 {
    // Replace .mini with .ll
    if (mem.endsWith(u8, path, ".mini")) {
        const base = path[0 .. path.len - 5];
        return std.fmt.allocPrint(allocator, "{s}.ll", .{base});
    }
    return std.fmt.allocPrint(allocator, "{s}.ll", .{path});
}

fn cleanCache(allocator: mem.Allocator) !void {
    _ = allocator;
    // Remove cache directory - deleteTree succeeds even if dir doesn't exist
    fs.cwd().deleteTree(CACHE_DIR) catch {};
    std.debug.print("[clean] Cache cleared\n", .{});
}

// Re-export for tests
const lexer = @import("lexer.zig");
const sema_mod = @import("sema.zig");

test {
    std.testing.refAllDecls(@This());
    _ = lexer;
    _ = sema_mod;
    _ = ast_mod;
    _ = zir_mod;
    _ = codegen_mod;
    _ = unit_mod;
    _ = cache_mod;
}
