---
title: "5b.6: Building and Running"
weight: 6
---

# Lesson 5b.6: Building and Running

Execute your generated LLVM IR.

---

## Goal

Learn to interpret and compile LLVM IR to native executables.

---

## LLVM Tools

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         LLVM TOOLCHAIN                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tool     Purpose                                                           │
│   ────     ───────                                                           │
│   lli      LLVM interpreter - runs IR directly                              │
│   llc      LLVM compiler - IR to assembly                                   │
│   opt      LLVM optimizer - runs optimization passes                        │
│   llvm-as  Assembler - text IR (.ll) to binary IR (.bc)                    │
│   llvm-dis Disassembler - binary IR (.bc) to text IR (.ll)                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Method 1: Direct Interpretation with lli

The simplest way to run LLVM IR:

```bash
# Create a test file
cat > test.ll << 'EOF'
define i32 @main() {
entry:
    ret i32 42
}
EOF

# Run it directly
lli test.ll
echo $?  # Output: 42
```

Fast for testing, but slower than compiled code.

---

## Method 2: Compile to Native

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    COMPILATION PIPELINE                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   test.ll ──────► test.s ──────► test.o ──────► test                        │
│      │              │              │              │                          │
│      │     llc      │    as/cc     │     ld      │                          │
│      │              │              │              │                          │
│   LLVM IR      Assembly       Object        Executable                       │
│                                                                              │
│   Or use clang to do it all:                                                │
│   clang test.ll -o test                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Step by Step

```bash
# 1. LLVM IR to Assembly
llc test.ll -o test.s

# 2. Assembly to Object File
as test.s -o test.o    # or: cc -c test.s -o test.o

# 3. Link to Executable
cc test.o -o test

# 4. Run
./test
echo $?  # Output: 42
```

### Or Use Clang Directly

```bash
# Clang handles everything
clang test.ll -o test
./test
```

---

## Optimization Levels

```bash
# No optimization (fast compilation)
llc -O0 test.ll -o test.s

# Basic optimization
llc -O1 test.ll -o test.s

# Full optimization
llc -O2 test.ll -o test.s

# Aggressive optimization
llc -O3 test.ll -o test.s
```

---

## Using the Optimizer

Run optimization passes before compiling:

```bash
# Optimize the IR
opt -O2 test.ll -o test_opt.bc

# View optimized IR
llvm-dis test_opt.bc -o test_opt.ll
cat test_opt.ll

# Compile optimized version
llc test_opt.bc -o test.s
```

---

## Complete Workflow Script

```bash
#!/bin/bash
# compile.sh - Compile our mini language

# 1. Run our compiler to generate LLVM IR
./mini-compiler input.mini > output.ll

# Check for errors
if [ $? -ne 0 ]; then
    echo "Compilation failed"
    exit 1
fi

# 2. Optimize (optional)
opt -O2 output.ll -o output.bc

# 3. Compile to executable
clang output.bc -o program

# 4. Run
./program
echo "Exit code: $?"
```

---

## Viewing Generated Assembly

```bash
# Generate assembly
llc test.ll -o test.s

# View it
cat test.s
```

Example output (x86-64):
```asm
	.text
	.globl	main
main:
	movl	$42, %eax
	retq
```

The optimizer reduced our function to just "return 42"!

---

## Cross Compilation

LLVM supports many targets:

```bash
# List available targets
llc --version

# Compile for different architectures
llc -march=arm64 test.ll -o test_arm.s
llc -march=x86-64 test.ll -o test_x64.s
llc -march=riscv64 test.ll -o test_riscv.s

# WebAssembly!
llc -march=wasm32 test.ll -o test.wasm
```

---

## Debugging LLVM IR

### Verify IR is Valid

```bash
# Check for errors
opt -verify test.ll -o /dev/null

# More verbose checking
llvm-as test.ll  # Will error if IR is malformed
```

### Common Errors

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    COMMON LLVM IR ERRORS                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Error                          Fix                                        │
│   ─────                          ───                                        │
│   "use of undefined value"       Reference before definition                │
│   "type mismatch"                Wrong type in operation                    │
│   "block does not have terminator" Missing ret/br at end of block          │
│   "redefinition of '%x'"         Duplicate value name                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Example

```bash
# test.ll - A complete program
cat > test.ll << 'EOF'
define i32 @add(i32 %a, i32 %b) {
entry:
    %sum = add i32 %a, %b
    ret i32 %sum
}

define i32 @main() {
entry:
    %result = call i32 @add(i32 3, i32 5)
    ret i32 %result
}
EOF

# Interpret
lli test.ll
echo "lli result: $?"

# Compile and run
clang test.ll -o test
./test
echo "compiled result: $?"
```

Output:
```
lli result: 8
compiled result: 8
```

---

## Performance Comparison

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    EXECUTION METHODS                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Method              Speed        Use Case                                  │
│   ──────              ─────        ────────                                  │
│   lli (interpreter)   Slowest      Quick testing                            │
│   llc -O0 + link      Fast         Debug builds                             │
│   llc -O2 + link      Faster       Release builds                           │
│   llc -O3 + link      Fastest      Maximum performance                      │
│                                                                              │
│   For development: use lli                                                   │
│   For production: use llc -O2 or -O3                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Integration with Our Compiler

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    COMPLETE PIPELINE                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   source.mini                                                                │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────────────────────────┐                                   │
│   │         Our Mini Compiler           │                                   │
│   │   Lexer → Parser → Sema → Codegen   │                                   │
│   └─────────────────┬───────────────────┘                                   │
│                     │                                                        │
│                     ▼                                                        │
│               output.ll (LLVM IR)                                           │
│                     │                                                        │
│          ┌─────────┴─────────┐                                              │
│          ▼                   ▼                                              │
│   ┌────────────┐      ┌────────────┐                                        │
│   │    lli     │      │   clang    │                                        │
│   │ (interpret)│      │ (compile)  │                                        │
│   └────────────┘      └─────┬──────┘                                        │
│                             │                                                │
│                             ▼                                                │
│                        executable                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Understanding

### Question 1
What's the fastest way to test LLVM IR during development?

Answer: Use `lli` to interpret it directly. No compilation step needed.

### Question 2
How do you compile LLVM IR with optimizations?

Answer: Use `llc -O2` or `clang -O2` to apply optimization passes.

### Question 3
What command compiles LLVM IR for ARM?

Answer: `llc -march=arm64 input.ll -o output.s`

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    LLVM BACKEND SUMMARY                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   You've learned to:                                                         │
│                                                                              │
│   1. Generate LLVM IR from AIR                                              │
│      • Map types to LLVM types                                              │
│      • Generate function definitions                                         │
│      • Emit arithmetic and control instructions                             │
│                                                                              │
│   2. Execute LLVM IR                                                        │
│      • lli for interpretation                                               │
│      • llc + clang for compilation                                          │
│      • Cross-compilation to other architectures                             │
│                                                                              │
│   3. Optimize                                                                │
│      • Use -O2/-O3 for production builds                                    │
│      • Use opt for specific passes                                          │
│                                                                              │
│   The LLVM backend gives you industrial-strength optimization               │
│   and multi-platform support with minimal additional effort!                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

You now have two complete backends for your mini compiler:
- **C Backend** (Section 5): Simple, portable, readable output
- **LLVM Backend** (Section 5b): Optimized, multi-target, professional

Continue to [Section 6: Complete Compiler](../../06-complete/) to wire everything together.
