---
title: "6.1: Integration"
weight: 1
---

# Lesson 6.1: Wiring Everything Together

Connect all compiler stages into one pipeline.

---

## Goal

Create a `compile(source) → output` function that runs the full pipeline.

---

## The Pipeline Function

```
function compile(source_code) → string:
    // Stage 1: Lexer
    tokens = tokenize(source_code)

    // Stage 2: Parser
    ast = parse(tokens)

    // Stage 3: ZIR Generation
    zir = generateZIR(ast)

    // Stage 4: Semantic Analysis
    result = analyze(zir)
    if result.errors.hasErrors():
        printErrors(result.errors)
        return null
    air = result.air

    // Stage 5: Code Generation
    c_code = generateProgram(air)

    return c_code
```

---

## Error Handling

```
function compile(source_code) → CompileResult:
    errors = ErrorCollector()

    // Lexer errors (invalid characters)
    tokens = tokenize(source_code, errors)
    if errors.hasErrors():
        return CompileResult { success: false, errors: errors }

    // Parser errors (syntax errors)
    ast = parse(tokens, errors)
    if errors.hasErrors():
        return CompileResult { success: false, errors: errors }

    // ZIR generation (shouldn't fail if parsing succeeded)
    zir = generateZIR(ast)

    // Sema errors (type errors, undefined variables)
    air = analyze(zir, errors)
    if errors.hasErrors():
        return CompileResult { success: false, errors: errors }

    // Code generation (shouldn't fail if sema succeeded)
    c_code = generateProgram(air)

    return CompileResult {
        success: true,
        output: c_code,
        errors: errors
    }
```

---

## Command-Line Interface

```
function main(args):
    if length(args) < 2:
        print("Usage: compiler <source_file>")
        exit(1)

    source_file = args[1]
    source_code = readFile(source_file)

    result = compile(source_code)

    if not result.success:
        for error in result.errors:
            printError(error)
        exit(1)

    print(result.output)
    exit(0)
```

Usage:
```bash
./compiler source.mini > output.c
cc output.c -o program
./program
```

---

## All-in-One Script

```bash
#!/bin/bash
# compile_and_run.sh

SOURCE=$1
if [ -z "$SOURCE" ]; then
    echo "Usage: $0 <source_file>"
    exit 1
fi

# Compile to C
./compiler "$SOURCE" > /tmp/output.c
if [ $? -ne 0 ]; then
    echo "Compilation failed"
    exit 1
fi

# Compile C to executable
cc /tmp/output.c -o /tmp/program
if [ $? -ne 0 ]; then
    echo "C compilation failed"
    exit 1
fi

# Run
/tmp/program
echo "Exit code: $?"
```

---

## Stage Outputs for Debugging

```
function compileVerbose(source_code):
    print("=== Source ===")
    print(source_code)

    print("\n=== Tokens ===")
    tokens = tokenize(source_code)
    for token in tokens:
        print(token)

    print("\n=== AST ===")
    ast = parse(tokens)
    printAST(ast)

    print("\n=== ZIR ===")
    zir = generateZIR(ast)
    printZIR(zir)

    print("\n=== AIR ===")
    air = analyze(zir)
    printAIR(air)

    print("\n=== Generated C ===")
    code = generateProgram(air)
    print(code)
```

---

## Module Structure

```
compiler/
├── main           # Entry point, CLI
├── lexer          # Tokenization
├── parser         # AST generation
├── zir            # ZIR data types
├── zir_gen        # AST → ZIR
├── sema           # Semantic analysis
├── air            # AIR data types
├── codegen        # AIR → C code
├── errors         # Error handling
└── types          # Type definitions
```

---

## Testing Integration

```
function testCompile(source, expected_exit_code):
    result = compile(source)
    assert result.success

    writeFile("/tmp/test.c", result.output)

    system("cc /tmp/test.c -o /tmp/test")
    exit_code = system("/tmp/test")

    assert exit_code == expected_exit_code
```

---

## Verify Your Implementation

### Test 1: Simple program
```
Source:
fn main() i32 { return 42; }

Steps:
1. compile() returns success
2. C code is valid
3. Compiled program returns 42
```

### Test 2: Error handling
```
Source:
fn main() i32 { return x; }

Steps:
1. compile() returns failure
2. Error message: "Undefined variable 'x'"
```

### Test 3: Complex program
```
Source:
fn add(a: i32, b: i32) i32 { return a + b; }
fn main() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    return x + y;
}

Steps:
1. compile() returns success
2. Program compiles and runs
3. Returns 8
```

---

## What's Next

Let's trace through a complete example.

Next: [Lesson 6.2: Walkthrough](../02-walkthrough/) →
