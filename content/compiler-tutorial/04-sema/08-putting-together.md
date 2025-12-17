---
title: "4.8: Complete Sema"
weight: 8
---

# Lesson 4.8: Putting It All Together

Let's assemble the complete semantic analyzer.

---

## Goal

Create an `analyze(zir)` function that validates and transforms ZIR into AIR.

---

## Complete Sema Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         COMPLETE SEMA                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Sema {                                                                     │
│       errors: ErrorCollector                                                │
│       symbol_table: SymbolTable                                             │
│       param_types: Type[]                                                   │
│       return_type: Type                                                     │
│       type_of: Type[]          // Type of each instruction                 │
│                                                                              │
│       // Analysis                                                            │
│       analyzeFunction(fn_zir) → FunctionAIR                                 │
│       analyzeInstruction(instr) → AIRInstruction                            │
│                                                                              │
│       // Type checking                                                       │
│       inferType(instr) → Type                                               │
│       checkBinaryOp(op, lhs, rhs) → Type                                   │
│       checkReturn(type)                                                      │
│                                                                              │
│       // Name resolution                                                     │
│       resolveReference(name) → Symbol                                       │
│   }                                                                          │
│                                                                              │
│   function analyze(program_zir) → ProgramAIR:                               │
│       functions = []                                                         │
│       for fn in program_zir.functions:                                      │
│           functions.append(analyzeFunction(fn))                             │
│       return ProgramAIR { functions }                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Code Summary

### Data Structures
```
enum Type { I32, I64, BOOL, VOID, ERROR }

Symbol {
    name: string,
    type: Type,
    kind: SymbolKind,  // PARAM or LOCAL
    index: integer
}

SymbolTable {
    symbols: Map<string, Symbol>,
    next_local_slot: integer
}
```

### Analyze Function
```
function analyzeFunction(fn_zir) → FunctionAIR:
    // Initialize
    symbol_table = SymbolTable()
    errors = ErrorCollector()

    // Resolve parameter types and add to symbol table
    param_types = []
    for i, param in enumerate(fn_zir.params):
        type = resolveType(param.type)
        param_types.append(type)
        symbol_table.declareParam(param.name, type, i)

    return_type = resolveType(fn_zir.return_type)

    // First pass: infer types
    type_of = []
    for instr in fn_zir.instructions:
        type_of.append(inferType(instr, type_of, symbol_table))

    // Second pass: generate AIR
    air_instructions = []
    for i, instr in enumerate(fn_zir.instructions):
        air = generateAIR(instr, type_of, symbol_table)
        air_instructions.append(air)

    return FunctionAIR {
        name: fn_zir.name,
        param_types: param_types,
        return_type: return_type,
        local_count: symbol_table.next_local_slot,
        instructions: air_instructions
    }
```

### Type Inference
```
function inferType(instr, type_of, symbol_table) → Type:
    switch instr.tag:
        CONSTANT:
            return I32

        PARAM_REF:
            return param_types[instr.data.param_index]

        DECL_REF:
            symbol = symbol_table.lookup(instr.data.name)
            if symbol == null:
                errors.report("Undefined variable: " + instr.data.name)
                return ERROR
            return symbol.type

        DECL:
            value_type = type_of[instr.data.value]
            symbol_table.declareLocal(instr.data.name, value_type, true)
            return VOID

        ADD, SUB, MUL, DIV:
            lhs = type_of[instr.data.lhs]
            rhs = type_of[instr.data.rhs]
            return checkBinaryOp(instr.tag, lhs, rhs)

        NEGATE:
            operand = type_of[instr.data.operand]
            return checkUnary(operand)

        RET:
            value_type = type_of[instr.data.value]
            checkReturn(value_type, return_type)
            return value_type

        RET_VOID:
            checkReturn(VOID, return_type)
            return VOID
```

### Type Checking
```
function checkBinaryOp(op, lhs, rhs) → Type:
    if lhs == ERROR or rhs == ERROR:
        return ERROR

    if lhs != rhs:
        errors.report("Type mismatch: " + typeName(lhs) + " vs " + typeName(rhs))
        return ERROR

    if lhs != I32 and lhs != I64:
        errors.report("Cannot perform arithmetic on " + typeName(lhs))
        return ERROR

    return lhs

function checkReturn(actual, expected):
    if actual == ERROR:
        return
    if actual != expected:
        errors.report("Return type mismatch: expected " +
                      typeName(expected) + ", got " + typeName(actual))
```

### AIR Generation
```
function generateAIR(instr, type_of, symbol_table) → AIRInstruction:
    switch instr.tag:
        CONSTANT:
            return ConstI32 { value: instr.data.value }

        PARAM_REF:
            return ParamGet {
                index: instr.data.param_index,
                type: param_types[instr.data.param_index]
            }

        DECL_REF:
            symbol = symbol_table.lookup(instr.data.name)
            if symbol.kind == PARAM:
                return ParamGet { index: symbol.index, type: symbol.type }
            else:
                return LocalGet { slot: symbol.index, type: symbol.type }

        DECL:
            symbol = symbol_table.lookup(instr.data.name)
            return LocalSet {
                slot: symbol.index,
                value: instr.data.value
            }

        ADD, SUB, MUL, DIV:
            result_type = type_of[current_index]
            tag = selectBinaryTag(instr.tag, result_type)
            return BinaryOp { tag, lhs: instr.data.lhs, rhs: instr.data.rhs }

        NEGATE:
            result_type = type_of[current_index]
            tag = (result_type == I32) ? NEG_I32 : NEG_I64
            return UnaryOp { tag, operand: instr.data.operand }

        RET:
            return Ret { value: instr.data.value }

        RET_VOID:
            return RetVoid {}
```

---

## Full Test Suite

### Test 1: Simple function
```
Input:
fn main() i32 {
    return 42;
}

AIR:
    function "main":
      param_types: []
      return_type: i32
      local_count: 0
      instructions:
        %0 = const_i32(42)
        %1 = ret(%0)
```

### Test 2: With parameters
```
Input:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

AIR:
    function "add":
      param_types: [i32, i32]
      return_type: i32
      local_count: 0
      instructions:
        %0 = param_get(0)
        %1 = param_get(1)
        %2 = add_i32(%0, %1)
        %3 = ret(%2)
```

### Test 3: With locals
```
Input:
fn calc() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    return x + y;
}

AIR:
    function "calc":
      param_types: []
      return_type: i32
      local_count: 2
      instructions:
        %0 = const_i32(5)
        %1 = local_set(0, %0)
        %2 = const_i32(3)
        %3 = local_set(1, %2)
        %4 = local_get(0)
        %5 = local_get(1)
        %6 = add_i32(%4, %5)
        %7 = ret(%6)
```

### Test 4: Type error
```
Input:
fn foo(a: i32, b: i64) i32 {
    return a + b;
}

Result: Error "Type mismatch: i32 vs i64"
```

### Test 5: Undefined variable
```
Input:
fn foo() i32 {
    return x;
}

Result: Error "Undefined variable: x"
```

### Test 6: Complex function
```
Input:
fn compute(n: i32) i32 {
    const doubled: i32 = n * 2;
    const result: i32 = doubled + 1;
    return result;
}

AIR:
    function "compute":
      param_types: [i32]
      return_type: i32
      local_count: 2
      instructions:
        %0 = param_get(0)
        %1 = const_i32(2)
        %2 = mul_i32(%0, %1)
        %3 = local_set(0, %2)
        %4 = local_get(0)
        %5 = const_i32(1)
        %6 = add_i32(%4, %5)
        %7 = local_set(1, %6)
        %8 = local_get(1)
        %9 = ret(%8)
```

---

## Integration: Full Pipeline

```
function compile(source):
    tokens = tokenize(source)       // Lexer
    ast = parse(tokens)             // Parser
    zir = generateZIR(ast)          // ZIR Generator
    air = analyze(zir)              // Sema
    return air

// Test
source = "fn main() i32 { return 42; }"
air = compile(source)
assert air.functions[0].instructions[0].tag == CONST_I32
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SEMA SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. TYPE SYSTEM      Define types: i32, i64, bool, void                   │
│   2. TYPE INFERENCE   Determine expression types                            │
│   3. SYMBOL TABLE     Track declared names                                  │
│   4. NAME RESOLUTION  Convert strings to locations                         │
│   5. TYPE CHECKING    Verify types match                                    │
│   6. AIR OUTPUT       Generate typed instructions                          │
│   7. ERROR HANDLING   Report meaningful messages                            │
│   8. INTEGRATION      Put it all together                                   │
│                                                                              │
│   Lines of code: ~150-200 depending on language                             │
│                                                                              │
│   Input:  ZIR (untyped, string names)                                       │
│   Output: AIR (typed, resolved locations)                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

We have typed IR! Time to generate actual code.

Next: [Section 5: Code Generation](../../05-codegen/) →
