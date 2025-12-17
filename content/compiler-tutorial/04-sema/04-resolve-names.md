---
title: "4.4: Resolve Names"
weight: 4
---

# Lesson 4.4: Resolving Name References

Transform string names into concrete locations.

---

## Goal

Convert `decl_ref("x")` into `local_get(slot)` or `param_get(index)`.

---

## The Problem

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        NAME RESOLUTION                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ZIR uses string names:                                                    │
│     %2 = decl_ref("x")    // Which "x"? Where is it?                       │
│                                                                              │
│   AIR uses concrete locations:                                              │
│     %2 = local_get(0)     // Local variable slot 0                         │
│     OR                                                                      │
│     %2 = param_get(1)     // Parameter index 1                             │
│                                                                              │
│   Resolution: lookup name → find symbol → use its location                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Resolution Process

```
function resolveReference(name, symbol_table) → AIRInstruction:
    symbol = symbol_table.lookup(name)

    if symbol == null:
        error("Undefined variable: " + name)
        return ErrorInstr {}

    switch symbol.kind:
        PARAM:
            return ParamGet {
                index: symbol.index,
                type: symbol.type
            }
        LOCAL:
            return LocalGet {
                slot: symbol.index,
                type: symbol.type
            }
```

---

## Full Instruction Analysis

```
function analyzeInstruction(zir_instr, symbol_table, type_of) → AIRInstruction:
    switch zir_instr.tag:

        CONSTANT:
            return Constant {
                value: zir_instr.data.value,
                type: I32
            }

        PARAM_REF:
            index = zir_instr.data.param_index
            // Look up parameter type from function signature
            type = param_types[index]
            return ParamGet {
                index: index,
                type: type
            }

        DECL_REF:
            name = zir_instr.data.name
            return resolveReference(name, symbol_table)

        DECL:
            name = zir_instr.data.name
            value_ref = zir_instr.data.value
            value_type = type_of[value_ref]

            slot = symbol_table.declareLocal(name, value_type, true)

            return LocalSet {
                slot: slot,
                value: value_ref,
                type: value_type
            }

        ADD, SUB, MUL, DIV:
            lhs = zir_instr.data.lhs
            rhs = zir_instr.data.rhs
            result_type = type_of[...]  // From type inference

            return BinaryOp {
                op: zir_instr.tag,
                lhs: lhs,
                rhs: rhs,
                type: result_type
            }

        // ... other cases
```

---

## Example Walkthrough

```
Source:
fn calc(n: i32) i32 {
    const doubled: i32 = n * 2;
    return doubled;
}

ZIR:
    %0 = param_ref(0)
    %1 = constant(2)
    %2 = mul(%0, %1)
    %3 = decl("doubled", %2)
    %4 = decl_ref("doubled")
    %5 = ret(%4)

Symbol table starts with:
    { "n": { kind: PARAM, index: 0, type: I32 } }

Analysis:

%0 = param_ref(0):
    → ParamGet { index: 0, type: I32 }

%1 = constant(2):
    → Constant { value: 2, type: I32 }

%2 = mul(%0, %1):
    → MulI32 { lhs: 0, rhs: 1, type: I32 }

%3 = decl("doubled", %2):
    Declare local: symbols["doubled"] = { kind: LOCAL, slot: 0, type: I32 }
    → LocalSet { slot: 0, value: 2, type: I32 }

%4 = decl_ref("doubled"):
    Lookup "doubled" → { kind: LOCAL, slot: 0, type: I32 }
    → LocalGet { slot: 0, type: I32 }

%5 = ret(%4):
    → Ret { value: 4, type: I32 }

Final symbol table:
    {
        "n": { kind: PARAM, index: 0, type: I32 },
        "doubled": { kind: LOCAL, slot: 0, type: I32 }
    }
```

---

## Handling Errors

```
function analyzeInstruction(zir_instr, ...):
    switch zir_instr.tag:
        DECL_REF:
            symbol = symbol_table.lookup(zir_instr.data.name)
            if symbol == null:
                error("Undefined variable '" + zir_instr.data.name + "'")
                // Return error instruction to allow continued analysis
                return ErrorInstr { type: ERROR }
            // ... normal case

        DECL:
            if symbol_table.isDeclared(zir_instr.data.name):
                error("Variable '" + zir_instr.data.name + "' already declared")
                return ErrorInstr { type: ERROR }
            // ... normal case
```

---

## Order Matters

Variables must be declared before use:

```
return x;           // Error: x not yet declared
const x: i32 = 5;

ZIR processes top-to-bottom:
    %0 = decl_ref("x")   // Lookup fails! x not in symbol table yet
    %1 = constant(5)
    %2 = decl("x", %1)
```

This is correct behavior - using undefined variables is an error.

---

## Verify Your Implementation

### Test 1: Parameter reference
```
Function: fn foo(a: i32) i32 { return a; }
ZIR: param_ref(0)
AIR: ParamGet { index: 0, type: I32 }
```

### Test 2: Local reference
```
Source:
    const x: i32 = 5;
    return x;

ZIR:
    %0 = constant(5)
    %1 = decl("x", %0)
    %2 = decl_ref("x")

AIR:
    %0 = Constant { value: 5, type: I32 }
    %1 = LocalSet { slot: 0, value: 0, type: I32 }
    %2 = LocalGet { slot: 0, type: I32 }
```

### Test 3: Multiple locals
```
Source:
    const a: i32 = 1;
    const b: i32 = 2;
    return a + b;

Symbol table after processing:
    { "a": slot 0, "b": slot 1 }

decl_ref("a") → LocalGet { slot: 0 }
decl_ref("b") → LocalGet { slot: 1 }
```

### Test 4: Undefined variable
```
Source: return undefined_var;
Result: Error "Undefined variable 'undefined_var'"
```

### Test 5: Duplicate declaration
```
Source:
    const x: i32 = 1;
    const x: i32 = 2;
Result: Error "Variable 'x' already declared"
```

---

## What's Next

Now let's verify types match correctly.

Next: [Lesson 4.5: Type Check](../05-type-check/) →
