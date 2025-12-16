//! Mini Zig Compiler
//!
//! A subset Zig compiler demonstrating the real Zig compiler pipeline:
//! Source → Lexer → Parser → AST → ZIR → Sema → AIR → Codegen → C
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

// Re-export key types
pub const Token = token.Token;
pub const TokenType = token.TokenType;
pub const Lexer = lexer.Lexer;
pub const Node = ast.Node;
pub const Parser = parser.Parser;
pub const ZirGenerator = zir.Generator;
pub const Analyzer = sema.Analyzer;
pub const CodeGenerator = codegen.Generator;
pub const GeneratedCode = codegen.GeneratedCode;

/// Compilation errors
pub const CompileError = error{
    LexError,
    ParseError,
    ZirGenError,
    SemaError,
    CodeGenError,
    OutOfMemory,
};

/// Compile source code to C code
pub fn compile(source: []const u8, allocator: Allocator) !GeneratedCode {
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

    // Stage 4: Code generation (AIR → C)
    var code_gen = CodeGenerator.init(allocator);
    code_gen.generate(air_insts) catch return CompileError.CodeGenError;

    return code_gen.finalize() catch return CompileError.OutOfMemory;
}

/// Compile with debug output showing all stages
pub fn compileWithDebug(source: []const u8, allocator: Allocator) !GeneratedCode {
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
    var code_gen = CodeGenerator.init(allocator);
    code_gen.generate(air_insts) catch |err| {
        std.debug.print("Codegen error: {any}\n", .{err});
        return CompileError.CodeGenError;
    };

    const generated = code_gen.finalize() catch return CompileError.OutOfMemory;

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("GENERATED C:\n============================================================\n{s}\n", .{generated.c_source});

    return generated;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
    std.debug.print("║   Source → Lexer → Parser → AST → ZIR → Sema → AIR → C      ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});

    var generated = compileWithDebug(source, allocator) catch |err| {
        std.debug.print("\nCompilation failed: {any}\n", .{err});
        return;
    };
    defer generated.deinit(allocator);

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("SUCCESS! Generated {d} bytes of C code.\n", .{generated.c_source.len});
    std.debug.print("============================================================\n", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "compile simple function" {
    const allocator = std.testing.allocator;

    const source =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var generated = try compile(source, allocator);
    defer generated.deinit(allocator);

    try std.testing.expect(generated.c_source.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, generated.c_source, "add") != null);
}

test "compile with arithmetic" {
    const allocator = std.testing.allocator;

    const source =
        \\pub fn calc(x: i32) i32 {
        \\    return x + 5 * 2;
        \\}
    ;

    var generated = try compile(source, allocator);
    defer generated.deinit(allocator);

    try std.testing.expect(generated.c_source.len > 0);
}

test {
    // Run all tests from imported modules
    std.testing.refAllDecls(@This());
}
