//! Mini Zig Compiler
//!
//! A subset Zig compiler demonstrating the real Zig compiler pipeline:
//! Source → Lexer → Parser → AST → ZIR → Sema → AIR → Codegen
//!
//! Supports multiple backends (like the real Zig compiler):
//! - C backend: Generates portable C code
//! - LLVM backend: Generates LLVM IR (can be compiled with llc/clang)
//!
//! Supports:
//! - Functions: pub fn add(a: i32, b: i32) i32 { ... }
//! - Declarations: const x: i32 = 5; var y: i32 = 10;
//! - Arithmetic: + - * /
//! - Control flow: if/else, while
//! - Types: i32, i64, bool, void

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import all compiler stages
pub const token = @import("token.zig");
pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const zir = @import("zir.zig");
pub const sema = @import("sema.zig");
pub const air = @import("air.zig");
pub const codegen = @import("codegen.zig");
pub const llvm_codegen = @import("llvm_codegen.zig");

// Re-export key types
pub const Token = token.Token;
pub const TokenType = token.TokenType;
pub const Lexer = lexer.Lexer;
pub const Node = ast.Node;
pub const Parser = parser.Parser;
pub const ZirGenerator = zir.Generator;
pub const Analyzer = sema.Analyzer;
pub const CCodeGenerator = codegen.Generator;
pub const LLVMCodeGenerator = llvm_codegen.Generator;
pub const GeneratedCCode = codegen.GeneratedCode;
pub const GeneratedLLVMIR = llvm_codegen.GeneratedIR;

/// Backend selection (like Zig's -fbackend option)
pub const Backend = enum {
    /// Generate C code (portable, requires C compiler)
    c,
    /// Generate LLVM IR (requires LLVM/clang)
    llvm,
};

/// Compilation errors
pub const CompileError = error{
    LexError,
    ParseError,
    ZirGenError,
    SemaError,
    CodeGenError,
    OutOfMemory,
};

/// Compilation result - either C code or LLVM IR
pub const CompileResult = union(Backend) {
    c: GeneratedCCode,
    llvm: GeneratedLLVMIR,

    pub fn deinit(self: *CompileResult, allocator: Allocator) void {
        switch (self.*) {
            .c => |*c| c.deinit(allocator),
            .llvm => |*ll| ll.deinit(allocator),
        }
    }

    pub fn getSource(self: CompileResult) []const u8 {
        return switch (self) {
            .c => |c| c.c_source,
            .llvm => |ll| ll.ll_source,
        };
    }
};

/// Compile source code to C code (default backend)
pub fn compile(source: []const u8, allocator: Allocator) !GeneratedCCode {
    return compileWithBackend(source, allocator, .c).c;
}

/// Compile source code with specified backend
pub fn compileWithBackend(source: []const u8, allocator: Allocator, backend: Backend) !CompileResult {
    // Use arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Stage 1: Parse source to AST
    var p = Parser.init(source, arena_alloc);
    const ast_root = p.parse() catch return CompileError.ParseError;

    // Stage 2: Generate ZIR from AST
    var zir_gen = ZirGenerator.init(arena_alloc);
    zir_gen.generate(ast_root) catch return CompileError.ZirGenError;

    // Stage 3: Semantic analysis (ZIR → AIR)
    var analyzer = Analyzer.init(arena_alloc);
    const air_insts = analyzer.analyze(zir_gen.getInstructions()) catch return CompileError.SemaError;

    // Stage 4: Code generation (AIR → target)
    switch (backend) {
        .c => {
            var code_gen = CCodeGenerator.init(allocator);
            code_gen.generate(air_insts) catch return CompileError.CodeGenError;
            return CompileResult{ .c = code_gen.finalize() catch return CompileError.OutOfMemory };
        },
        .llvm => {
            var code_gen = LLVMCodeGenerator.init(allocator);
            defer code_gen.deinit();
            code_gen.generate(air_insts) catch return CompileError.CodeGenError;
            return CompileResult{ .llvm = code_gen.finalize() catch return CompileError.OutOfMemory };
        },
    }
}

/// Compile with debug output showing all stages
pub fn compileWithDebug(source: []const u8, allocator: Allocator, backend: Backend) !CompileResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("SOURCE:\n============================================================\n{s}\n", .{source});

    // Stage 1: Parse
    var p = Parser.init(source, arena_alloc);
    const ast_root = p.parse() catch |err| {
        std.debug.print("Parse error: {any}\n", .{err});
        return CompileError.ParseError;
    };

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("AST:\n============================================================\n", .{});
    const stderr_file = std.fs.File.stderr();
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = stderr_file.writer(&stderr_buf);
    ast_root.dump(&stderr_writer.interface, 0) catch {};
    stderr_writer.interface.flush() catch {};

    // Stage 2: ZIR
    var zir_gen = ZirGenerator.init(arena_alloc);
    zir_gen.generate(ast_root) catch |err| {
        std.debug.print("ZIR error: {any}\n", .{err});
        return CompileError.ZirGenError;
    };

    std.debug.print("\n", .{});
    zir_gen.dump(&stderr_writer.interface) catch {};
    stderr_writer.interface.flush() catch {};

    // Stage 3: Sema → AIR
    var analyzer = Analyzer.init(arena_alloc);
    const air_insts = analyzer.analyze(zir_gen.getInstructions()) catch |err| {
        std.debug.print("Sema error: {any}\n", .{err});
        return CompileError.SemaError;
    };

    std.debug.print("\n", .{});
    air.dump(air_insts, &stderr_writer.interface) catch {};
    stderr_writer.interface.flush() catch {};

    // Stage 4: Codegen
    const backend_name = switch (backend) {
        .c => "C",
        .llvm => "LLVM IR",
    };

    switch (backend) {
        .c => {
            var code_gen = CCodeGenerator.init(allocator);
            code_gen.generate(air_insts) catch |err| {
                std.debug.print("Codegen error: {any}\n", .{err});
                return CompileError.CodeGenError;
            };

            const generated = code_gen.finalize() catch return CompileError.OutOfMemory;

            std.debug.print("\n============================================================\n", .{});
            std.debug.print("GENERATED {s}:\n============================================================\n{s}\n", .{ backend_name, generated.c_source });

            return CompileResult{ .c = generated };
        },
        .llvm => {
            var code_gen = LLVMCodeGenerator.init(allocator);
            defer code_gen.deinit();
            code_gen.generate(air_insts) catch |err| {
                std.debug.print("Codegen error: {any}\n", .{err});
                return CompileError.CodeGenError;
            };

            const generated = code_gen.finalize() catch return CompileError.OutOfMemory;

            std.debug.print("\n============================================================\n", .{});
            std.debug.print("GENERATED {s}:\n============================================================\n{s}\n", .{ backend_name, generated.ll_source });

            return CompileResult{ .llvm = generated };
        },
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: mini-compiler [options]
        \\
        \\Options:
        \\  --backend=c      Generate C code (default)
        \\  --backend=llvm   Generate LLVM IR
        \\  --both           Generate both C and LLVM IR
        \\  -o <file>        Output file (default: output.c or output.ll)
        \\  --help           Show this help
        \\
        \\Examples:
        \\  mini-compiler --backend=c -o main.c     # Output to main.c
        \\  mini-compiler --backend=llvm -o out.ll  # Output to out.ll
        \\  mini-compiler --both                    # Both backends
        \\
    , .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var backend: ?Backend = null;
    var show_both = false;
    var output_file: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--backend=c")) {
            backend = .c;
        } else if (std.mem.eql(u8, arg, "--backend=llvm")) {
            backend = .llvm;
        } else if (std.mem.eql(u8, arg, "--both")) {
            show_both = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            if (i + 1 < args.len) {
                i += 1;
                output_file = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        }
    }

    // Default to C backend if no specific backend is chosen
    if (backend == null and !show_both) {
        backend = .c;
    }

    // Test program
    const source =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\
        \\pub fn main() i32 {
        \\    const x: i32 = 5;
        \\    const y: i32 = 3;
        \\    const result: i32 = add(x, y);
        \\    return result;
        \\}
    ;

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║           MINI ZIG COMPILER - Pipeline Demo                  ║\n", .{});
    std.debug.print("║   Source → Lexer → Parser → AST → ZIR → Sema → AIR          ║\n", .{});
    std.debug.print("║                                                              ║\n", .{});
    std.debug.print("║   Backends: C (default), LLVM IR                             ║\n", .{});
    std.debug.print("║   Usage: mini-compiler --backend=c|llvm|--both               ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});

    // Compile with selected backend(s)
    if (show_both or backend == .c) {
        std.debug.print("\n", .{});
        std.debug.print("╭──────────────────────────────────────────────────────────────╮\n", .{});
        std.debug.print("│                    C BACKEND                                 │\n", .{});
        std.debug.print("╰──────────────────────────────────────────────────────────────╯\n", .{});

        var c_result = compileWithDebug(source, allocator, .c) catch |err| {
            std.debug.print("\nC compilation failed: {any}\n", .{err});
            return;
        };
        defer c_result.deinit(allocator);

        // Write to file
        const c_filename = output_file orelse "output.c";
        const c_file = try std.fs.cwd().createFile(c_filename, .{});
        defer c_file.close();
        try c_file.writeAll(c_result.getSource());

        std.debug.print("\n============================================================\n", .{});
        std.debug.print("SUCCESS! Wrote {d} bytes to {s}\n", .{ c_result.getSource().len, c_filename });
    }

    if (show_both or backend == .llvm) {
        std.debug.print("\n", .{});
        std.debug.print("╭──────────────────────────────────────────────────────────────╮\n", .{});
        std.debug.print("│                    LLVM BACKEND                              │\n", .{});
        std.debug.print("╰──────────────────────────────────────────────────────────────╯\n", .{});

        var llvm_result = compileWithDebug(source, allocator, .llvm) catch |err| {
            std.debug.print("\nLLVM compilation failed: {any}\n", .{err});
            return;
        };
        defer llvm_result.deinit(allocator);

        // Write to file
        const ll_filename = if (output_file != null and backend == .llvm) output_file.? else "output.ll";
        const ll_file = try std.fs.cwd().createFile(ll_filename, .{});
        defer ll_file.close();
        try ll_file.writeAll(llvm_result.getSource());

        std.debug.print("\n============================================================\n", .{});
        std.debug.print("SUCCESS! Wrote {d} bytes to {s}\n", .{ llvm_result.getSource().len, ll_filename });
    }

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                    COMPILATION COMPLETE                      ║\n", .{});
    std.debug.print("║                                                              ║\n", .{});
    std.debug.print("║   To compile the output:                                     ║\n", .{});
    std.debug.print("║   C:    cc output.c -o output                                ║\n", .{});
    std.debug.print("║   LLVM: clang output.ll -o output                            ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "compile simple function to C" {
    const allocator = std.testing.allocator;

    const source =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var result = try compileWithBackend(source, allocator, .c);
    defer result.deinit(allocator);

    try std.testing.expect(result.getSource().len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.getSource(), "add") != null);
}

test "compile simple function to LLVM" {
    const allocator = std.testing.allocator;

    const source =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var result = try compileWithBackend(source, allocator, .llvm);
    defer result.deinit(allocator);

    try std.testing.expect(result.getSource().len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.getSource(), "define") != null);
}

test "compile with arithmetic" {
    const allocator = std.testing.allocator;

    const source =
        \\pub fn calc(x: i32) i32 {
        \\    return x + 5 * 2;
        \\}
    ;

    var c_result = try compileWithBackend(source, allocator, .c);
    defer c_result.deinit(allocator);
    try std.testing.expect(c_result.getSource().len > 0);

    var llvm_result = try compileWithBackend(source, allocator, .llvm);
    defer llvm_result.deinit(allocator);
    try std.testing.expect(llvm_result.getSource().len > 0);
}

test {
    // Run all tests from imported modules
    std.testing.refAllDecls(@This());
}
