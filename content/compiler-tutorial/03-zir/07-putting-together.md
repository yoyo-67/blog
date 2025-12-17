---
title: "3.7: Complete ZIR"
weight: 7
---

# Lesson 3.7: Putting It All Together

Let's assemble the complete ZIR generator.

---

## Goal

Create a `generateZIR(ast)` function that transforms an AST into ZIR.

---

## Complete ZIR Generator Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       COMPLETE ZIR GENERATOR                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ZIRGenerator {                                                             │
│       instructions: Instruction[]                                            │
│       param_names: Map<string, integer>                                      │
│                                                                              │
│       // Core                                                                │
│       emit(instruction) → InstrRef                                          │
│                                                                              │
│       // Expressions                                                         │
│       generateExpr(expr) → InstrRef                                         │
│                                                                              │
│       // Statements                                                          │
│       generateStatement(stmt)                                                │
│       generateVarDecl(stmt)                                                  │
│       generateReturn(stmt)                                                   │
│       generateBlock(block)                                                   │
│                                                                              │
│       // Functions                                                           │
│       generateFunction(fn_decl) → FunctionZIR                               │
│   }                                                                          │
│                                                                              │
│   function generateZIR(ast) → ProgramZIR:                                   │
│       functions = []                                                         │
│       for decl in ast.declarations:                                         │
│           functions.append(generateFunction(decl))                          │
│       return ProgramZIR { functions }                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Code Summary

### Data Structures
```
InstrRef = integer

enum InstrTag {
    CONSTANT, ADD, SUB, MUL, DIV, NEGATE,
    DECL, DECL_REF, PARAM_REF, RET, RET_VOID
}

Instruction { tag: InstrTag, data: ... }

FunctionZIR {
    name: string,
    params: Parameter[],
    return_type: TypeExpr,
    instructions: Instruction[]
}

ProgramZIR {
    functions: FunctionZIR[]
}
```

### Generator State
```
ZIRGenerator {
    instructions: Instruction[]
    param_names: Map<string, integer>
}

function emit(instruction) → InstrRef:
    index = length(instructions)
    instructions.append(instruction)
    return index
```

### Expression Generation
```
function generateExpr(expr) → InstrRef:
    switch expr.type:
        NumberExpr:
            return emit(Constant { value: expr.value })

        IdentifierExpr:
            if expr.name in param_names:
                return emit(ParamRef { index: param_names[expr.name] })
            return emit(DeclRef { name: expr.name })

        UnaryExpr:
            operand = generateExpr(expr.operand)
            return emit(Negate { operand: operand })

        BinaryExpr:
            lhs = generateExpr(expr.left)
            rhs = generateExpr(expr.right)
            return emit(binaryOp(expr.operator, lhs, rhs))

function binaryOp(operator, lhs, rhs) → Instruction:
    switch operator.type:
        PLUS:  return Add { lhs, rhs }
        MINUS: return Sub { lhs, rhs }
        STAR:  return Mul { lhs, rhs }
        SLASH: return Div { lhs, rhs }
```

### Statement Generation
```
function generateStatement(stmt):
    switch stmt.type:
        VarDecl:
            value = generateExpr(stmt.value)
            emit(Decl { name: stmt.name, value: value })

        ReturnStmt:
            if stmt.value != null:
                value = generateExpr(stmt.value)
                emit(Ret { value: value })
            else:
                emit(RetVoid {})

        Block:
            for s in stmt.statements:
                generateStatement(s)
```

### Function Generation
```
function generateFunction(fn_decl) → FunctionZIR:
    param_names = {}
    for i, param in enumerate(fn_decl.params):
        param_names[param.name] = i

    generator = ZIRGenerator {
        instructions: [],
        param_names: param_names
    }

    for stmt in fn_decl.body.statements:
        generator.generateStatement(stmt)

    return FunctionZIR {
        name: fn_decl.name,
        params: fn_decl.params,
        return_type: fn_decl.return_type,
        instructions: generator.instructions
    }
```

### Entry Point
```
function generateZIR(ast) → ProgramZIR:
    functions = []
    for decl in ast.declarations:
        functions.append(generateFunction(decl))
    return ProgramZIR { functions: functions }
```

---

## Full Test Suite

### Test 1: Minimal function
```
Input:
fn main() i32 {
    return 0;
}

ZIR:
function "main":
  params: []
  return_type: i32
  body:
    %0 = constant(0)
    %1 = ret(%0)
```

### Test 2: Arithmetic
```
Input:
fn calc() i32 {
    return 1 + 2 * 3;
}

ZIR:
function "calc":
  params: []
  return_type: i32
  body:
    %0 = constant(1)
    %1 = constant(2)
    %2 = constant(3)
    %3 = mul(%1, %2)
    %4 = add(%0, %3)
    %5 = ret(%4)
```

### Test 3: Parameters
```
Input:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

ZIR:
function "add":
  params: [("a", i32), ("b", i32)]
  return_type: i32
  body:
    %0 = param_ref(0)
    %1 = param_ref(1)
    %2 = add(%0, %1)
    %3 = ret(%2)
```

### Test 4: Local variables
```
Input:
fn compute() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    return x + y;
}

ZIR:
function "compute":
  params: []
  return_type: i32
  body:
    %0 = constant(5)
    %1 = decl("x", %0)
    %2 = constant(3)
    %3 = decl("y", %2)
    %4 = decl_ref("x")
    %5 = decl_ref("y")
    %6 = add(%4, %5)
    %7 = ret(%6)
```

### Test 5: Full program
```
Input:
fn square(x: i32) i32 {
    return x * x;
}

fn main() i32 {
    return 0;
}

ZIR:
function "square":
  params: [("x", i32)]
  return_type: i32
  body:
    %0 = param_ref(0)
    %1 = param_ref(0)
    %2 = mul(%0, %1)
    %3 = ret(%2)

function "main":
  params: []
  return_type: i32
  body:
    %0 = constant(0)
    %1 = ret(%0)
```

### Test 6: Complex function
```
Input:
fn calc(a: i32, b: i32) i32 {
    const sum: i32 = a + b;
    const doubled: i32 = sum * 2;
    return doubled;
}

ZIR:
function "calc":
  params: [("a", i32), ("b", i32)]
  return_type: i32
  body:
    %0 = param_ref(0)
    %1 = param_ref(1)
    %2 = add(%0, %1)
    %3 = decl("sum", %2)
    %4 = decl_ref("sum")
    %5 = constant(2)
    %6 = mul(%4, %5)
    %7 = decl("doubled", %6)
    %8 = decl_ref("doubled")
    %9 = ret(%8)
```

---

## Integration: Full Pipeline

```
function compile(source):
    tokens = tokenize(source)     // Lexer
    ast = parse(tokens)           // Parser
    zir = generateZIR(ast)        // ZIR Generator
    return zir

// Test
source = "fn main() i32 { return 42; }"
zir = compile(source)
assert zir.functions[0].name == "main"
assert zir.functions[0].instructions[0].tag == CONSTANT
assert zir.functions[0].instructions[0].data.constant_value == 42
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         ZIR SUMMARY                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. IR INSTRUCTIONS   Define instruction types                             │
│   2. FLATTEN EXPR      Simple expressions → linear form                     │
│   3. NESTED EXPR       Complex expressions with precedence                  │
│   4. NAME REFS         Variable declarations and references                 │
│   5. PARAM REFS        Function parameter references                        │
│   6. FUNCTION IR       Complete function structures                         │
│   7. INTEGRATION       Put it all together                                  │
│                                                                              │
│   Lines of code: ~80-120 depending on language                              │
│                                                                              │
│   ZIR is UNTYPED:                                                           │
│   - Names are strings, not resolved                                         │
│   - Types are recorded but not checked                                      │
│   - That's Sema's job!                                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

We have linear IR, but names are still strings and types aren't checked. Time for semantic analysis!

Next: [Section 4: Sema (Semantic Analysis)](../../04-sema/) →
