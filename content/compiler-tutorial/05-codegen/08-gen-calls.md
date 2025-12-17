---
title: "5.8: Calls"
weight: 8
---

# Lesson 5.8: Generating Function Calls

Emit code for calling functions.

---

## Goal

Generate C code for function call instructions.

---

## Note: Our Mini Language

Our mini compiler doesn't include function calls in its core feature set. This lesson shows how you'd add them as an extension.

---

## Call Pattern

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        FUNCTION CALLS                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source:    x = add(1, 2)                                                  │
│                                                                              │
│   AIR:       %0 = const_i32(1)                                              │
│              %1 = const_i32(2)                                              │
│              %2 = call("add", [%0, %1])                                     │
│                                                                              │
│   C:         int32_t t0 = 1;                                                │
│              int32_t t1 = 2;                                                │
│              int32_t t2 = add(t0, t1);                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## If You Add Calls

### AIR Instruction

```
Call {
    name: string,         // Function name
    args: InstrRef[],     // Argument references
    type: Type            // Return type
}
```

### Code Generation

```
function generateCall(instr, index):
    // Only emit result variable if non-void
    if instr.type != VOID:
        emitIndent()
        emit(typeToCType(instr.type))
        emit(" t")
        emit(index)
        emit(" = ")

    // Function name and arguments
    emit(instr.data.name)
    emit("(")

    for i, arg in enumerate(instr.data.args):
        if i > 0:
            emit(", ")
        emit("t")
        emit(arg)

    emitLine(");")
```

---

## Examples

### Non-void call
```
AIR: call("add", [%0, %1]) at index 2, type i32

C: int32_t t2 = add(t0, t1);
```

### Void call
```
AIR: call("print", [%0]) at index 3, type void

C: print(t0);
```

### No arguments
```
AIR: call("getTime", []) at index 0, type i64

C: int64_t t0 = getTime();
```

---

## Forward Declarations

If function B calls function A, and A is defined after B:

```
// Forward declaration
int32_t add(int32_t p0, int32_t p1);

// Uses add
int32_t compute() {
    return add(1, 2);
}

// Defines add
int32_t add(int32_t p0, int32_t p1) {
    return p0 + p1;
}
```

### Generate Forward Declarations

```
function generateForwardDeclarations(program_air):
    for fn in program_air.functions:
        generateFunctionSignature(fn)
        emitLine(";")
    emitLine("")
```

---

## Recursive Calls

Forward declarations also enable recursion:

```
// Forward declaration required
int32_t factorial(int32_t n);

int32_t factorial(int32_t n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}
```

---

## Verify Your Implementation

### Test 1: Simple call
```
AIR:
    %0 = const_i32(3)
    %1 = const_i32(5)
    %2 = call("add", [%0, %1]), type i32

Output:
    int32_t t0 = 3;
    int32_t t1 = 5;
    int32_t t2 = add(t0, t1);
```

### Test 2: Void call
```
AIR:
    %0 = const_i32(42)
    %1 = call("print", [%0]), type void

Output:
    int32_t t0 = 42;
    print(t0);
```

### Test 3: No arguments
```
AIR:
    %0 = call("random", []), type i32

Output:
    int32_t t0 = random();
```

### Test 4: Many arguments
```
AIR:
    %0 = const_i32(1)
    %1 = const_i32(2)
    %2 = const_i32(3)
    %3 = call("sum3", [%0, %1, %2]), type i32

Output:
    int32_t t0 = 1;
    int32_t t1 = 2;
    int32_t t2 = 3;
    int32_t t3 = sum3(t0, t1, t2);
```

---

## What's Next

Let's put together the complete program structure.

Next: [Lesson 5.9: Program](../09-gen-program/) →
