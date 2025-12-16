//! Mini Math Compiler - Main Entry Point
//!
//! Demonstrates the complete compiler pipeline:
//! Lexer → Parser → Semantic Analysis → Optimizer → IR → CodeGen → VM

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import all compiler stages
pub const token = @import("token.zig");
pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const sema = @import("sema.zig");
pub const optimizer = @import("optimizer.zig");
pub const ir = @import("ir.zig");
pub const codegen = @import("codegen.zig");
pub const vm = @import("vm.zig");

// Re-export key types
pub const Token = token.Token;
pub const TokenType = token.TokenType;
pub const Lexer = lexer.Lexer;
pub const Node = ast.Node;
pub const Parser = parser.Parser;
pub const Analyzer = sema.Analyzer;
pub const Optimizer = optimizer.Optimizer;
pub const IrGenerator = ir.Generator;
pub const CodeGenerator = codegen.Generator;
pub const VM = vm.VM;
pub const Value = vm.Value;
pub const CompiledCode = codegen.CompiledCode;

/// Compilation errors
pub const CompileError = error{
    LexError,
    ParseError,
    SemanticError,
    OptimizeError,
    IrGenError,
    CodeGenError,
    OutOfMemory,
};

/// Compile source code to bytecode
pub fn compile(source: []const u8, allocator: Allocator) CompileError!CompiledCode {
    // Stage 1 & 2: Lexing and Parsing
    var p = Parser.init(source, allocator);
    const ast_root = p.parse() catch return CompileError.ParseError;

    // Stage 3: Semantic Analysis
    var analyzer = Analyzer.init(allocator);
    defer analyzer.deinit();
    _ = analyzer.analyze(ast_root) catch return CompileError.SemanticError;

    // Stage 4: Optimization
    var opt = Optimizer.init(allocator);
    const optimized_ast = opt.optimize(ast_root) catch return CompileError.OptimizeError;

    // Stage 5: IR Generation
    var ir_gen = IrGenerator.init(allocator);
    defer ir_gen.deinit();
    ir_gen.generate(optimized_ast) catch return CompileError.IrGenError;

    // Stage 6: Code Generation
    var code_gen = CodeGenerator.init(allocator);
    defer code_gen.deinit();
    code_gen.generate(ir_gen.getInstructions()) catch return CompileError.CodeGenError;

    return code_gen.finalize() catch return CompileError.OutOfMemory;
}

/// Compile and run source code, returning the result
pub fn run(source: []const u8, allocator: Allocator) !Value {
    var compiled = try compile(source, allocator);
    defer compiled.deinit(allocator);

    var virtual_machine = VM.init(compiled);
    return virtual_machine.run();
}

/// Compile and run with debug output
pub fn runWithDebug(source: []const u8, allocator: Allocator) !Value {
    const stderr = std.io.getStdErr().writer();

    try stderr.print("\n=== Source ===\n{s}\n", .{source});

    // Parse
    var p = Parser.init(source, allocator);
    const ast_root = p.parse() catch |err| {
        try stderr.print("Parse error: {any}\n", .{err});
        return CompileError.ParseError;
    };

    try stderr.writeAll("\n=== AST ===\n");
    try ast_root.dump(stderr, 0);

    // Semantic Analysis
    var analyzer = Analyzer.init(allocator);
    defer analyzer.deinit();
    const typed = analyzer.analyze(ast_root) catch |err| {
        try stderr.print("Semantic error: {any}\n", .{err});
        return CompileError.SemanticError;
    };
    try stderr.print("\n=== Type ===\n{any}\n", .{typed.value_type});

    // Optimization
    var opt = Optimizer.init(allocator);
    const optimized_ast = try opt.optimize(ast_root);
    try stderr.print("\n=== Optimized AST ({d} optimizations) ===\n", .{opt.getOptimizationCount()});
    try optimized_ast.dump(stderr, 0);

    // IR Generation
    var ir_gen = IrGenerator.init(allocator);
    defer ir_gen.deinit();
    try ir_gen.generate(optimized_ast);
    try stderr.writeAll("\n=== IR ===\n");
    try ir_gen.dump(stderr);

    // Code Generation
    var code_gen = CodeGenerator.init(allocator);
    defer code_gen.deinit();
    try code_gen.generate(ir_gen.getInstructions());
    var compiled = try code_gen.finalize();
    defer compiled.deinit(allocator);

    try stderr.writeAll("\n=== Bytecode ===\n");
    try compiled.dump(stderr);

    // Execution
    try stderr.writeAll("\n=== Execution ===\n");
    var virtual_machine = VM.init(compiled);
    virtual_machine.enableTrace();
    const result = try virtual_machine.run();

    try stderr.print("\n=== Result ===\n{any}\n", .{result});
    return result;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_cases = [_]struct { source: []const u8, expected: []const u8 }{
        .{ .source = "42", .expected = "42" },
        .{ .source = "3 + 5", .expected = "8" },
        .{ .source = "3 + 5 * 2", .expected = "13" },
        .{ .source = "(3 + 5) * 2", .expected = "16" },
        .{ .source = "-5 + 3", .expected = "-2" },
        .{ .source = "10 - 3 - 2", .expected = "5" },
        .{ .source = "100 / 10 / 2", .expected = "5" },
        .{ .source = "17 % 5", .expected = "2" },
        .{ .source = "2.5 * 4", .expected = "10" },
        .{ .source = "3.14 + 2.86", .expected = "6" },
        .{ .source = "x = 10; y = 20; x + y", .expected = "30" },
        .{ .source = "a = 5; b = a * 2; b + 3", .expected = "13" },
        .{ .source = "-(3 + 4)", .expected = "-7" },
        .{ .source = "--5", .expected = "5" },
    };

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║        MINI MATH COMPILER (Modular) - Test Results           ║\n", .{});
    std.debug.print("╠══════════════════════════════════════════════════════════════╣\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    for (test_cases) |tc| {
        const result = run(tc.source, allocator) catch |err| {
            std.debug.print("║ FAIL: \"{s}\"\n", .{tc.source});
            std.debug.print("║       Error: {any}\n", .{err});
            failed += 1;
            continue;
        };

        var buf: [32]u8 = undefined;
        const result_str = switch (result) {
            .int => |i| std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?",
            .float => |f| std.fmt.bufPrint(&buf, "{d:.0}", .{f}) catch "?",
        };

        const status = if (std.mem.eql(u8, result_str, tc.expected)) "PASS" else "FAIL";
        if (std.mem.eql(u8, status, "PASS")) {
            passed += 1;
        } else {
            failed += 1;
        }

        std.debug.print("║ {s}: \"{s}\" = {s}", .{ status, tc.source, result_str });
        if (!std.mem.eql(u8, result_str, tc.expected)) {
            std.debug.print(" (expected {s})", .{tc.expected});
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("╠══════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║ Results: {d} passed, {d} failed                                 ║\n", .{ passed, failed });
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "end-to-end compile and run" {
    const allocator = std.testing.allocator;

    const result = try run("3 + 5 * 2", allocator);
    try std.testing.expectEqual(Value{ .int = 13 }, result);
}

test "variables" {
    const allocator = std.testing.allocator;

    const result = try run("x = 10; y = 20; x + y", allocator);
    try std.testing.expectEqual(Value{ .int = 30 }, result);
}

test "float arithmetic" {
    const allocator = std.testing.allocator;

    const result = try run("2.5 * 4", allocator);
    try std.testing.expectEqual(@as(f64, 10.0), result.float);
}

test {
    // Run all tests from imported modules
    std.testing.refAllDecls(@This());
}
