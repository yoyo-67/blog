---
title: "5c.6: Generating Functions"
weight: 6
---

# Lesson 5c.6: Generating Functions

Handle parameters, locals, and function structure.

---

## Goal

Generate bytecode for function definitions, including parameter access and local variables.

---

## Function Structure

Each function needs:
- Its bytecode (the instructions)
- Metadata (name, number of parameters, number of locals)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       FUNCTION METADATA                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Function:                                                                  │
│       name: "add"                                                           │
│       num_params: 2                                                         │
│       num_locals: 0                                                         │
│       code_offset: 0        ← where bytecode starts                         │
│       code_length: 6        ← bytes of code                                 │
│                                                                              │
│   Bytecode:                                                                  │
│       LOAD_PARAM 0          ← push first param                              │
│       LOAD_PARAM 1          ← push second param                             │
│       ADD_I32                                                                │
│       RET                                                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Stack Frame

When a function runs, the VM sets up a **stack frame**:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          STACK FRAME                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   function foo(a: i32, b: i32) i32 {                                        │
│       var x: i32 = 10;                                                      │
│       return a + b + x;                                                     │
│   }                                                                          │
│                                                                              │
│   Stack during execution:                                                    │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────┐               │
│   │  ...caller's stack...  │  a  │  b  │  x  │ temporaries │               │
│   └─────────────────────────────────────────────────────────┘               │
│                             ↑                 ↑                             │
│                            BP                SP                             │
│                       (base pointer)    (stack pointer)                     │
│                                                                              │
│   BP points to start of this frame                                          │
│   Parameters: BP[0], BP[1]                                                  │
│   Locals: BP[num_params], BP[num_params+1], ...                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Loading Parameters

`LOAD_PARAM n` pushes parameter `n` onto the stack:

```
function generateParam(instr):
    emitByte(LOAD_PARAM)
    emitByte(instr.param_index)
```

Example:
```
AIR:    %0 = param(0)       ← first parameter
        %1 = param(1)       ← second parameter

Bytecode:
        LOAD_PARAM 0        ← [0x20, 0x00]
        LOAD_PARAM 1        ← [0x20, 0x01]
```

---

## Local Variables

For `const` and `var` declarations, we allocate a slot in the frame:

```
function generateLocalDecl(instr, local_index):
    // Value is already on stack from previous instruction
    emitByte(STORE_LOCAL)
    emitByte(local_index)
```

Wait, but we also need to push the value first!

---

## Declaration Flow

```
Source:
    const x: i32 = 5;
    return x + 1;

AIR:
    %0 = const_i32(5)
    %1 = decl_const("x", %0)
    %2 = load(x)             ← actually load(%1) referencing the decl
    %3 = const_i32(1)
    %4 = add_i32(%2, %3)
    %5 = ret(%4)

Bytecode generation:

    %0: PUSH_I32 5           ← value on stack
    %1: STORE_LOCAL 0        ← pop into local slot 0

    %2: LOAD_LOCAL 0         ← push local back onto stack
    %3: PUSH_I32 1
    %4: ADD_I32
    %5: RET
```

---

## Generate Declaration

```
function generateDecl(instr, local_index):
    // The value was already pushed by the value instruction
    emitByte(STORE_LOCAL)
    emitByte(local_index)
```

---

## Generate Load

```
function generateLoad(instr):
    emitByte(LOAD_LOCAL)
    emitByte(instr.local_index)
```

---

## Tracking Local Indices

The bytecode generator needs to track which local is at which index:

```
BytecodeGenerator:
    local_map: Map<name, index>
    next_local: integer = 0

    function allocateLocal(name):
        index = next_local
        local_map[name] = index
        next_local = next_local + 1
        return index

    function getLocal(name):
        return local_map[name]
```

---

## Full Example

```
Source:
    fn double(n: i32) i32 {
        const result: i32 = n + n;
        return result;
    }

AIR:
    decl_fn("double", [i32], i32):
        %0 = param(0)           ← n
        %1 = param(0)           ← n again
        %2 = add_i32(%0, %1)
        %3 = decl_const("result", %2)
        %4 = load(%3)
        %5 = ret(%4)

Bytecode:
    ; Function: double, 1 param, 1 local
    LOAD_PARAM 0        ← push n
    LOAD_PARAM 0        ← push n again
    ADD_I32             ← n + n on stack
    STORE_LOCAL 0       ← store in "result" (local 0)
    LOAD_LOCAL 0        ← push "result" back
    RET                 ← return it
```

---

## Optimized: Skip Redundant Store/Load

Notice `STORE_LOCAL 0; LOAD_LOCAL 0` is wasteful. We could optimize:

```
Before: STORE_LOCAL 0, LOAD_LOCAL 0
After:  (just leave value on stack)
```

But for simplicity, we'll keep the straightforward approach. Optimization can come later.

---

## Function Table

The generator builds a function table:

```
FunctionEntry:
    name: string
    num_params: integer
    num_locals: integer
    code: ByteArray

generateFunction(fn_decl):
    entry = new FunctionEntry()
    entry.name = fn_decl.name
    entry.num_params = fn_decl.params.length
    entry.num_locals = 0  // count as we go

    local_map.clear()

    for instr in fn_decl.body:
        generateInstruction(instr)
        if instr is decl_const or decl_var:
            entry.num_locals += 1

    entry.code = output.toBytes()
    functions.append(entry)
```

---

## Verify Your Implementation

### Test 1: Simple parameter use
```
fn identity(x: i32) i32 {
    return x;
}

Bytecode:
    LOAD_PARAM 0
    RET
```

### Test 2: Two parameters
```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

Bytecode:
    LOAD_PARAM 0
    LOAD_PARAM 1
    ADD_I32
    RET
```

### Test 3: Local variable
```
fn double(n: i32) i32 {
    const result: i32 = n + n;
    return result;
}

Bytecode:
    LOAD_PARAM 0
    LOAD_PARAM 0
    ADD_I32
    STORE_LOCAL 0
    LOAD_LOCAL 0
    RET
```

---

## What's Next

Let's handle function calls.

Next: [Lesson 5c.7: Generating Calls](../07-gen-calls/) →
