---
title: "5.10: Complete Codegen"
weight: 10
---

# Lesson 5.10: Putting It All Together

Let's assemble the complete code generator.

---

## Goal

Create a `generateCode(air)` function that produces compilable C code.

---

## Complete Codegen Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       COMPLETE CODEGEN                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CodeGenerator {                                                            │
│       output: StringBuilder                                                  │
│       indent: integer                                                        │
│                                                                              │
│       // Emission helpers                                                    │
│       emit(text)                                                             │
│       emitLine(text)                                                         │
│       emitIndent()                                                           │
│                                                                              │
│       // Type conversion                                                     │
│       typeToCType(type) → string                                            │
│                                                                              │
│       // Instruction generation                                              │
│       generateInstruction(instr, index)                                     │
│       generateConstant(instr, index)                                        │
│       generateBinaryOp(instr, index)                                        │
│       generateUnaryOp(instr, index)                                         │
│       generateParamGet(instr, index)                                        │
│       generateLocalGet(instr, index)                                        │
│       generateLocalSet(instr, index)                                        │
│       generateReturn(instr, index)                                          │
│                                                                              │
│       // Function generation                                                 │
│       generateFunction(fn_air)                                              │
│       generateFunctionSignature(fn_air)                                     │
│       emitLocalDeclarations(fn_air)                                         │
│                                                                              │
│       // Program generation                                                  │
│       generateProgram(program_air) → string                                 │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Code Summary

### Helpers
```
function emit(text):
    output.append(text)

function emitLine(text):
    emit(text)
    emit("\n")

function emitIndent():
    for i in range(indent):
        emit("    ")
```

### Type Conversion
```
function typeToCType(type) → string:
    switch type:
        I32:   return "int32_t"
        I64:   return "int64_t"
        BOOL:  return "bool"
        VOID:  return "void"
```

### Instruction Generation
```
function generateInstruction(instr, index):
    switch instr.tag:
        CONST_I32, CONST_I64, CONST_BOOL:
            generateConstant(instr, index)

        ADD_I32, ADD_I64, SUB_I32, SUB_I64,
        MUL_I32, MUL_I64, DIV_I32, DIV_I64:
            generateBinaryOp(instr, index)

        NEG_I32, NEG_I64:
            generateUnaryOp(instr, index)

        PARAM_GET:
            generateParamGet(instr, index)

        LOCAL_GET:
            generateLocalGet(instr, index)

        LOCAL_SET:
            generateLocalSet(instr, index)

        RET:
            generateReturn(instr, index)

        RET_VOID:
            emitIndent()
            emitLine("return;")
```

### Constant Generation
```
function generateConstant(instr, index):
    type_str = typeToCType(instr.type)
    value = formatValue(instr.data.value, instr.type)

    emitIndent()
    emit(type_str + " t" + index + " = " + value)
    emitLine(";")
```

### Binary Operation
```
function generateBinaryOp(instr, index):
    type_str = typeToCType(instr.type)
    op = airTagToOperator(instr.tag)
    lhs = instr.data.lhs
    rhs = instr.data.rhs

    emitIndent()
    emit(type_str + " t" + index + " = t" + lhs + " " + op + " t" + rhs)
    emitLine(";")
```

### Variable Access
```
function generateParamGet(instr, index):
    type_str = typeToCType(instr.type)
    emitIndent()
    emit(type_str + " t" + index + " = p" + instr.data.index)
    emitLine(";")

function generateLocalGet(instr, index):
    type_str = typeToCType(instr.type)
    emitIndent()
    emit(type_str + " t" + index + " = local_" + instr.data.slot)
    emitLine(";")

function generateLocalSet(instr, index):
    emitIndent()
    emit("local_" + instr.data.slot + " = t" + instr.data.value)
    emitLine(";")
```

### Return
```
function generateReturn(instr, index):
    emitIndent()
    emit("return t" + instr.data.value)
    emitLine(";")
```

### Function
```
function generateFunction(fn_air):
    generateFunctionSignature(fn_air)
    emitLine(" {")
    indent++

    emitLocalDeclarations(fn_air)
    if fn_air.local_count > 0:
        emitLine("")

    for i, instr in enumerate(fn_air.instructions):
        generateInstruction(instr, i)

    indent--
    emitLine("}")
```

### Program
```
function generateProgram(program_air) → string:
    output = StringBuilder()
    indent = 0

    emitLine("#include <stdint.h>")
    emitLine("#include <stdbool.h>")
    emitLine("")

    for fn in program_air.functions:
        generateFunctionSignature(fn)
        emitLine(";")
    emitLine("")

    for fn in program_air.functions:
        generateFunction(fn)
        emitLine("")

    return output.toString()
```

---

## Full Test Suite

### Test 1: Minimal program
```
Source:
fn main() i32 {
    return 0;
}

Output:
#include <stdint.h>
#include <stdbool.h>

int32_t main();

int32_t main() {
    int32_t t0 = 0;
    return t0;
}
```

### Test 2: Arithmetic
```
Source:
fn calc() i32 {
    return 1 + 2 * 3;
}

Output includes:
    int32_t t0 = 1;
    int32_t t1 = 2;
    int32_t t2 = 3;
    int32_t t3 = t1 * t2;
    int32_t t4 = t0 + t3;
    return t4;
```

### Test 3: Parameters
```
Source:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

Output:
int32_t add(int32_t p0, int32_t p1) {
    int32_t t0 = p0;
    int32_t t1 = p1;
    int32_t t2 = t0 + t1;
    return t2;
}
```

### Test 4: Local variables
```
Source:
fn calc() i32 {
    const x: i32 = 5;
    return x * 2;
}

Output includes:
    int32_t local_0;

    int32_t t0 = 5;
    local_0 = t0;
    int32_t t2 = local_0;
    int32_t t3 = 2;
    int32_t t4 = t2 * t3;
    return t4;
```

### Test 5: End-to-end compilation
```
Source:
fn main() i32 {
    return 42;
}

Commands:
    ./compiler source.mini > output.c
    cc output.c -o test
    ./test
    echo $?

Expected: 42
```

---

## Integration: Complete Compiler

```
function compile(source) → string:
    tokens = tokenize(source)         // Lexer
    ast = parse(tokens)               // Parser
    zir = generateZIR(ast)            // ZIR Generator
    air = analyze(zir)                // Sema
    code = generateProgram(air)       // Codegen
    return code
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        CODEGEN SUMMARY                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. TARGET CHOICE    Why we generate C                                     │
│   2. TYPE MAPPING     i32 → int32_t                                        │
│   3. CONSTANTS        int32_t t0 = 42;                                     │
│   4. BINARY OPS       t2 = t0 + t1;                                        │
│   5. VARIABLES        params (pN), locals (local_N), temps (tN)           │
│   6. FUNCTIONS        Signatures and bodies                                 │
│   7. RETURN           return tN;                                           │
│   8. CALLS            fn(t0, t1) (extension)                               │
│   9. PROGRAM          Headers and structure                                 │
│  10. INTEGRATION      Complete code generator                               │
│                                                                              │
│   Lines of code: ~100-150 depending on language                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

We have a complete compiler! Let's wire all the stages together.

Next: [Section 6: Complete Compiler](../../06-complete/) →
