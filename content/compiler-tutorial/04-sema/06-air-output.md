---
title: "4.6: AIR Output"
weight: 6
---

# Lesson 4.6: Generating AIR

Produce typed intermediate representation for code generation.

---

## Goal

Transform analyzed ZIR into AIR (Analyzed IR) with resolved names and types.

---

## AIR vs ZIR

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         ZIR vs AIR                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ZIR (input):                    AIR (output):                             │
│                                                                              │
│   decl_ref("x")                   local_get(slot: 0, type: i32)            │
│   param_ref(0)                    param_get(index: 0, type: i32)           │
│   add(%0, %1)                     add_i32(%0, %1)                           │
│   decl("x", %0)                   local_set(slot: 0, value: %0)            │
│                                                                              │
│   String names → Resolved slots                                             │
│   Unknown types → Explicit types                                            │
│   Generic ops → Type-specific ops                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## AIR Instruction Types

```
enum AIRTag {
    // Constants
    CONST_I32,
    CONST_I64,
    CONST_BOOL,

    // Arithmetic (type-specific)
    ADD_I32, ADD_I64,
    SUB_I32, SUB_I64,
    MUL_I32, MUL_I64,
    DIV_I32, DIV_I64,
    NEG_I32, NEG_I64,

    // Variables
    PARAM_GET,
    LOCAL_GET,
    LOCAL_SET,

    // Control
    RET,
    RET_VOID,
}

AIRInstruction {
    tag: AIRTag,
    type: Type,        // Result type
    data: AIRData,     // Tag-specific data
}
```

---

## Generating AIR

```
function generateAIR(zir_instr, type_of, symbol_table) → AIRInstruction:
    switch zir_instr.tag:

        CONSTANT:
            value = zir_instr.data.value
            return AIRInstruction {
                tag: CONST_I32,
                type: I32,
                data: { value: value }
            }

        PARAM_REF:
            index = zir_instr.data.param_index
            param_type = param_types[index]
            return AIRInstruction {
                tag: PARAM_GET,
                type: param_type,
                data: { index: index }
            }

        DECL_REF:
            symbol = symbol_table.lookup(zir_instr.data.name)
            if symbol.kind == PARAM:
                return AIRInstruction {
                    tag: PARAM_GET,
                    type: symbol.type,
                    data: { index: symbol.index }
                }
            else:  // LOCAL
                return AIRInstruction {
                    tag: LOCAL_GET,
                    type: symbol.type,
                    data: { slot: symbol.index }
                }

        ADD, SUB, MUL, DIV:
            result_type = type_of[current_index]
            tag = selectBinaryTag(zir_instr.tag, result_type)
            return AIRInstruction {
                tag: tag,
                type: result_type,
                data: {
                    lhs: zir_instr.data.lhs,
                    rhs: zir_instr.data.rhs
                }
            }

        DECL:
            symbol = symbol_table.lookup(zir_instr.data.name)
            return AIRInstruction {
                tag: LOCAL_SET,
                type: VOID,
                data: {
                    slot: symbol.index,
                    value: zir_instr.data.value
                }
            }

        NEGATE:
            result_type = type_of[current_index]
            tag = (result_type == I32) ? NEG_I32 : NEG_I64
            return AIRInstruction {
                tag: tag,
                type: result_type,
                data: { operand: zir_instr.data.operand }
            }

        RET:
            return AIRInstruction {
                tag: RET,
                type: type_of[zir_instr.data.value],
                data: { value: zir_instr.data.value }
            }

        RET_VOID:
            return AIRInstruction {
                tag: RET_VOID,
                type: VOID,
                data: {}
            }
```

---

## Select Type-Specific Tag

```
function selectBinaryTag(zir_tag, type) → AIRTag:
    switch zir_tag:
        ADD:
            return (type == I32) ? ADD_I32 : ADD_I64
        SUB:
            return (type == I32) ? SUB_I32 : SUB_I64
        MUL:
            return (type == I32) ? MUL_I32 : MUL_I64
        DIV:
            return (type == I32) ? DIV_I32 : DIV_I64
```

---

## Function AIR

```
FunctionAIR {
    name: string,
    param_types: Type[],
    return_type: Type,
    local_count: integer,      // Number of local variable slots
    instructions: AIRInstruction[]
}
```

---

## Full Example

```
Source:
fn add(a: i32, b: i32) i32 {
    const sum: i32 = a + b;
    return sum;
}

ZIR:
    %0 = param_ref(0)
    %1 = param_ref(1)
    %2 = add(%0, %1)
    %3 = decl("sum", %2)
    %4 = decl_ref("sum")
    %5 = ret(%4)

After Sema:
    Symbol table: { "a": param 0, "b": param 1, "sum": local 0 }
    Types: [I32, I32, I32, VOID, I32, I32]

AIR:
    %0 = param_get(index: 0)     // type: i32
    %1 = param_get(index: 1)     // type: i32
    %2 = add_i32(%0, %1)         // type: i32
    %3 = local_set(slot: 0, %2)  // type: void
    %4 = local_get(slot: 0)      // type: i32
    %5 = ret(%4)                 // type: i32

FunctionAIR {
    name: "add",
    param_types: [I32, I32],
    return_type: I32,
    local_count: 1,
    instructions: [...]
}
```

---

## Simplified Example

```
Source:
fn square(x: i32) i32 {
    return x * x;
}

ZIR:
    %0 = param_ref(0)
    %1 = param_ref(0)
    %2 = mul(%0, %1)
    %3 = ret(%2)

AIR:
    %0 = param_get(0)     // i32
    %1 = param_get(0)     // i32
    %2 = mul_i32(%0, %1)  // i32
    %3 = ret(%2)
```

---

## Verify Your Implementation

### Test 1: Constants
```
ZIR:  constant(42)
AIR:  const_i32(42), type: I32
```

### Test 2: Parameter access
```
Function params: [i32, i64]
ZIR:  param_ref(0)
AIR:  param_get(0), type: I32

ZIR:  param_ref(1)
AIR:  param_get(1), type: I64
```

### Test 3: Local variable
```
ZIR:
    %0 = constant(5)
    %1 = decl("x", %0)
    %2 = decl_ref("x")

AIR:
    %0 = const_i32(5), type: I32
    %1 = local_set(slot: 0, %0), type: VOID
    %2 = local_get(slot: 0), type: I32
```

### Test 4: Type-specific arithmetic
```
ZIR:  add(i32_expr, i32_expr)
AIR:  add_i32(...), type: I32

ZIR:  add(i64_expr, i64_expr)
AIR:  add_i64(...), type: I64
```

### Test 5: Full function
```
Source: fn inc(n: i32) i32 { return n + 1; }

AIR:
    param_types: [I32]
    return_type: I32
    local_count: 0
    instructions:
        %0 = param_get(0), type: I32
        %1 = const_i32(1), type: I32
        %2 = add_i32(%0, %1), type: I32
        %3 = ret(%2)
```

---

## What's Next

Let's handle error messages properly.

Next: [Lesson 4.7: Error Handling](../07-error-handling/) →
