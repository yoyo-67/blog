---
title: "5.5: Variables"
weight: 5
---

# Lesson 5.5: Generating Variables

Handle parameters and local variables.

---

## Goal

Generate C code for `param_get`, `local_get`, and `local_set`.

---

## Variable Naming

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        VARIABLE NAMING                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Parameters:   p0, p1, p2, ...  (from function signature)                  │
│   Locals:       local_0, local_1, local_2, ...  (declared in body)          │
│   Temporaries:  t0, t1, t2, ...  (instruction results)                      │
│                                                                              │
│   fn foo(a: i32, b: i32) i32 {     int32_t foo(int32_t p0, int32_t p1) {   │
│       const x: i32 = a + b;    →       int32_t local_0;                    │
│       return x;                        int32_t t0 = p0 + p1;               │
│   }                                    local_0 = t0;                        │
│                                        return local_0;                      │
│                                    }                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Parameter Access

```
AIR: param_get(index: 0) at instruction 2

C code: int32_t t2 = p0;
```

```
function generateParamGet(instr, index):
    type_str = typeToCType(instr.type)
    param_index = instr.data.index

    emitIndent()
    emit(type_str)
    emit(" t")
    emit(index)
    emit(" = p")
    emit(param_index)
    emitLine(";")
```

---

## Local Variable Get

```
AIR: local_get(slot: 0) at instruction 5

C code: int32_t t5 = local_0;
```

```
function generateLocalGet(instr, index):
    type_str = typeToCType(instr.type)
    slot = instr.data.slot

    emitIndent()
    emit(type_str)
    emit(" t")
    emit(index)
    emit(" = local_")
    emit(slot)
    emitLine(";")
```

---

## Local Variable Set

```
AIR: local_set(slot: 0, value: 3) at instruction 4

C code: local_0 = t3;
```

```
function generateLocalSet(instr, index):
    slot = instr.data.slot
    value = instr.data.value

    emitIndent()
    emit("local_")
    emit(slot)
    emit(" = t")
    emit(value)
    emitLine(";")

    // Note: local_set doesn't produce a value, so no tN = ...
```

---

## Declaring Local Variables

At the start of the function, declare all locals:

```
function emitLocalDeclarations(fn_air):
    for slot in range(fn_air.local_count):
        emitIndent()
        emit("int32_t local_")   // Or proper type if tracked
        emit(slot)
        emitLine(";")
```

Better approach with types:

```
function emitLocalDeclarations(fn_air, local_types):
    for slot in range(fn_air.local_count):
        type_str = typeToCType(local_types[slot])
        emitIndent()
        emit(type_str)
        emit(" local_")
        emit(slot)
        emitLine(";")
```

---

## Full Example

```
Source:
fn calc(n: i32) i32 {
    const doubled: i32 = n * 2;
    return doubled;
}

AIR:
    params: [i32]
    return_type: i32
    local_count: 1
    instructions:
        %0 = param_get(0)
        %1 = const_i32(2)
        %2 = mul_i32(%0, %1)
        %3 = local_set(0, %2)
        %4 = local_get(0)
        %5 = ret(%4)

Generated C:
    int32_t calc(int32_t p0) {
        int32_t local_0;        // Declaration
        int32_t t0 = p0;        // param_get(0)
        int32_t t1 = 2;         // const_i32(2)
        int32_t t2 = t0 * t1;   // mul_i32
        local_0 = t2;           // local_set(0, %2)
        int32_t t4 = local_0;   // local_get(0)
        return t4;              // ret(%4)
    }
```

---

## Optimization Note

The generated code is verbose:
```c
int32_t t0 = p0;
int32_t t2 = t0 * t1;
```

Could be simplified to:
```c
int32_t t2 = p0 * t1;
```

But! The C compiler will optimize this away. We generate simple, correct code and let `gcc -O2` handle the rest.

---

## Verify Your Implementation

### Test 1: Parameter get
```
AIR:    param_get(0) at index 2, type i32
Output: "int32_t t2 = p0;"
```

### Test 2: Second parameter
```
AIR:    param_get(1) at index 3, type i64
Output: "int64_t t3 = p1;"
```

### Test 3: Local get
```
AIR:    local_get(slot: 0) at index 5, type i32
Output: "int32_t t5 = local_0;"
```

### Test 4: Local set
```
AIR:    local_set(slot: 0, value: 3) at index 4
Output: "local_0 = t3;"
```

### Test 5: Local declarations
```
Function with 2 locals (both i32)
Output at function start:
    "int32_t local_0;"
    "int32_t local_1;"
```

### Test 6: Full function
```
fn foo(x: i32) i32 {
    const y: i32 = x + 1;
    return y;
}

Output:
    int32_t foo(int32_t p0) {
        int32_t local_0;
        int32_t t0 = p0;
        int32_t t1 = 1;
        int32_t t2 = t0 + t1;
        local_0 = t2;
        int32_t t4 = local_0;
        return t4;
    }
```

---

## What's Next

Let's generate function signatures.

Next: [Lesson 5.6: Functions](../06-gen-functions/) →
