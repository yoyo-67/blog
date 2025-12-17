---
title: "5.6: Functions"
weight: 6
---

# Lesson 5.6: Generating Functions

Emit complete function definitions.

---

## Goal

Generate C function signatures and bodies.

---

## Function Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      FUNCTION STRUCTURE                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   C function layout:                                                        │
│                                                                              │
│   return_type name(param_type p0, param_type p1, ...) {                    │
│       // Local variable declarations                                        │
│       type local_0;                                                         │
│       type local_1;                                                         │
│                                                                              │
│       // Instruction code                                                   │
│       type t0 = ...;                                                        │
│       type t1 = ...;                                                        │
│       ...                                                                   │
│   }                                                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Generate Function Signature

```
function generateFunctionSignature(fn_air):
    // Return type
    emit(typeToCType(fn_air.return_type))
    emit(" ")

    // Function name
    emit(fn_air.name)
    emit("(")

    // Parameters
    for i, param_type in enumerate(fn_air.param_types):
        if i > 0:
            emit(", ")
        emit(typeToCType(param_type))
        emit(" p")
        emit(i)

    emit(")")
```

---

## Examples

```
fn main() i32
→ int32_t main()

fn add(a: i32, b: i32) i32
→ int32_t add(int32_t p0, int32_t p1)

fn doSomething() void
→ void doSomething()

fn process(x: i64, y: i32, z: bool) i64
→ int64_t process(int64_t p0, int32_t p1, bool p2)
```

---

## Generate Full Function

```
function generateFunction(fn_air):
    // Signature
    generateFunctionSignature(fn_air)
    emitLine(" {")

    // Increase indentation
    indent = indent + 1

    // Local variable declarations
    emitLocalDeclarations(fn_air)

    // Empty line for readability
    if fn_air.local_count > 0:
        emitLine("")

    // Instructions
    for i, instr in enumerate(fn_air.instructions):
        generateInstruction(instr, i)

    // Decrease indentation
    indent = indent - 1

    emitLine("}")
```

---

## Full Example

```
Source:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

AIR:
    name: "add"
    param_types: [i32, i32]
    return_type: i32
    local_count: 0
    instructions:
        %0 = param_get(0)
        %1 = param_get(1)
        %2 = add_i32(%0, %1)
        %3 = ret(%2)

Generated C:
    int32_t add(int32_t p0, int32_t p1) {
        int32_t t0 = p0;
        int32_t t1 = p1;
        int32_t t2 = t0 + t1;
        return t2;
    }
```

---

## With Local Variables

```
Source:
fn calc(n: i32) i32 {
    const doubled: i32 = n * 2;
    return doubled;
}

Generated C:
    int32_t calc(int32_t p0) {
        int32_t local_0;

        int32_t t0 = p0;
        int32_t t1 = 2;
        int32_t t2 = t0 * t1;
        local_0 = t2;
        int32_t t4 = local_0;
        return t4;
    }
```

---

## Void Functions

```
Source:
fn doNothing() void {
    return;
}

Generated C:
    void doNothing() {
        return;
    }
```

---

## Verify Your Implementation

### Test 1: No parameters
```
fn_air:
    name: "foo"
    param_types: []
    return_type: i32

Signature: "int32_t foo()"
```

### Test 2: One parameter
```
fn_air:
    name: "inc"
    param_types: [i32]
    return_type: i32

Signature: "int32_t inc(int32_t p0)"
```

### Test 3: Multiple parameters
```
fn_air:
    name: "add3"
    param_types: [i32, i32, i32]
    return_type: i32

Signature: "int32_t add3(int32_t p0, int32_t p1, int32_t p2)"
```

### Test 4: Void return
```
fn_air:
    name: "noop"
    param_types: []
    return_type: void

Signature: "void noop()"
```

### Test 5: Full function with locals
```
fn_air:
    name: "test"
    param_types: [i32]
    return_type: i32
    local_count: 1

Output:
    int32_t test(int32_t p0) {
        int32_t local_0;
        ...
    }
```

---

## What's Next

Let's handle return statements.

Next: [Lesson 5.7: Return](../07-gen-return/) →
