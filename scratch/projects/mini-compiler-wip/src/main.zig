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
        const verbose = args.len > 3 and mem.eql(u8, args[3], "-v");
        try incrementalBuild(allocator, args[2], verbose);
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
        \\  run <file>       Compile and run the file
        \\  emit <file>      Emit LLVM IR to stdout
        \\  eval <code>      Compile and run code string
        \\  build <file> -v  Incremental build (with optional verbose)
        \\  clean            Clean the build cache
        \\
        \\Examples:
        \\  comp run example.mini
        \\  comp emit example.mini > output.ll
        \\  comp eval "fn main() i32 {{ return 42; }}"
        \\  comp build main.mini -v
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

fn incrementalBuild(allocator: mem.Allocator, path: []const u8, verbose: bool) !void {
    // Initialize multi-level cache
    var multi_cache = cache_mod.MultiLevelCache.init(allocator, CACHE_DIR);
    defer multi_cache.deinit();

    // Load all caches (file cache + AIR cache)
    try multi_cache.load();

    if (verbose) {
        std.debug.print("[cache] Loaded AIR cache with {d} functions\n", .{multi_cache.air_cache.entries.count()});
    }

    // Check if file needs recompilation
    const needs_recompile = try multi_cache.file_cache.needsRecompile(path);

    if (needs_recompile) {
        if (verbose) {
            std.debug.print("[build] File changed, recompiling: {s}\n", .{path});
        }

        // Compile using multi-level cache
        const result = try compileWithCache(allocator, path, &multi_cache, verbose);
        defer allocator.free(result.llvm_ir);

        // Get dependencies from compilation unit
        const deps = try collectDependencies(allocator, path);
        defer {
            for (deps) |dep| allocator.free(dep);
            allocator.free(deps);
        }

        // Update file-level cache
        try multi_cache.file_cache.update(path, result.llvm_ir, deps);

        // Save all caches (file cache + AIR cache)
        try multi_cache.save();

        if (verbose) {
            std.debug.print("[build] Cache stats - ZIR: {d} files, AIR: {d} functions\n", .{
                multi_cache.zir_cache.entries.count(),
                multi_cache.air_cache.entries.count(),
            });
            std.debug.print("[build] Functions: {d} cached, {d} compiled\n", .{
                result.functions_cached,
                result.functions_compiled,
            });
        }

        std.debug.print("[build] Compiled: {s}\n", .{path});

        // Write output
        const output_path = try getOutputPath(allocator, path);
        defer allocator.free(output_path);

        const out_file = try fs.cwd().createFile(output_path, .{});
        defer out_file.close();
        try out_file.writeAll(result.llvm_ir);

        std.debug.print("[build] Output: {s}\n", .{output_path});
    } else {
        if (verbose) {
            std.debug.print("[build] No changes, using cache: {s}\n", .{path});
        }

        // Use cached version
        if (multi_cache.file_cache.getCachedLLVMIR(path)) |cached_ir| {
            const output_path = try getOutputPath(allocator, path);
            defer allocator.free(output_path);

            const out_file = try fs.cwd().createFile(output_path, .{});
            defer out_file.close();
            try out_file.writeAll(cached_ir);

            std.debug.print("[build] Output (cached): {s}\n", .{output_path});
        } else {
            std.debug.print("[build] Cache miss, recompiling...\n", .{});
            // Fallback to full compile
            try incrementalBuild(allocator, path, verbose);
        }
    }
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
    verbose: bool,
) !CompileCacheResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Read source file
    const source = try readFile(arena_alloc, path);
    const source_hash = cache_mod.hashSource(source);

    // Check ZIR cache for this file
    if (multi_cache.zir_cache.get(path, source_hash)) |_| {
        if (verbose) {
            std.debug.print("[cache] ZIR cache hit: {s}\n", .{path});
        }
        // ZIR cache hit - but we still need to parse to get the AST for codegen
        // In a full implementation, we would serialize/deserialize ZIR
    }

    // Create compilation unit
    var unit = unit_mod.CompilationUnit.init(arena_alloc, path);
    try unit.load(&arena);

    // Load all imports
    var units: std.StringHashMapUnmanaged(*unit_mod.CompilationUnit) = .empty;
    try unit.loadImports(&arena, &units);

    // Generate program with all imported functions
    const program = try unit.generateProgram(arena_alloc);

    // Update ZIR cache with function names
    var func_names: std.ArrayListUnmanaged([]const u8) = .empty;
    for (program.functions()) |func| {
        try func_names.append(arena_alloc, func.name);
    }
    try multi_cache.zir_cache.put(path, source_hash, source_hash, func_names.items);

    // Generate LLVM IR using per-function AIR cache
    var cached_gen = cache_mod.CachedCodegen.init(allocator, &multi_cache.air_cache, path);
    const llvm_ir = try cached_gen.generate(program);

    return .{
        .llvm_ir = llvm_ir,
        .functions_cached = cached_gen.stats.functions_cached,
        .functions_compiled = cached_gen.stats.functions_compiled,
    };
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
