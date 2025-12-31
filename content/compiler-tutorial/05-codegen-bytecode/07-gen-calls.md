---
title: "5c.7: Generating Calls"
weight: 7
---

# Lesson 5c.7: Generating Calls

Handle function calls and returns.

---

## Goal

Generate bytecode for calling functions and returning from them.

---

## The CALL Instruction

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          CALL INSTRUCTION                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CALL <function_index> <arg_count>                                         │
│                                                                              │
│   Before:  [...][arg0][arg1][arg2]                                          │
│   After:   [...][return_value]                                              │
│                                                                              │
│   The VM:                                                                    │
│   1. Saves current position (return address)                                │
│   2. Creates new stack frame with arguments                                 │
│   3. Jumps to function's bytecode                                           │
│   4. When RET executes, returns to saved position                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Call Encoding

```
CALL:  [0x30] [fn_index: 2 bytes] [arg_count: 1 byte]

Example: CALL function 5 with 2 arguments
         [0x30] [0x05, 0x00] [0x02]
```

---

## Generate Call

```
function generateCall(instr):
    // First, generate code to push all arguments
    // (Already done by previous instructions)

    // Get function index from function table
    fn_index = getFunctionIndex(instr.callee_name)

    emitByte(CALL)
    emitU16(fn_index)
    emitByte(instr.args.length)
```

---

## Example: Calling add(3, 5)

```
Source:
    fn add(a: i32, b: i32) i32 { return a + b; }
    fn main() i32 { return add(3, 5); }

AIR for main:
    %0 = const_i32(3)
    %1 = const_i32(5)
    %2 = call("add", [%0, %1])
    %3 = ret(%2)

Bytecode for main:
    PUSH_I32 3          ← push first argument
    PUSH_I32 5          ← push second argument
    CALL 0 2            ← call function 0 with 2 args
    RET                 ← return the result

Stack trace:
    PUSH_I32 3   → [3]
    PUSH_I32 5   → [3][5]
    CALL 0 2     → (VM executes add, returns) → [8]
    RET          → returns 8
```

---

## The RET Instruction

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           RET INSTRUCTION                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   RET:                                                                       │
│       Before:  [caller's stack][args...][locals...][return_value]           │
│       After:   [caller's stack][return_value]                               │
│                                                                              │
│   The VM:                                                                    │
│   1. Pops return value                                                      │
│   2. Discards current frame (args + locals)                                 │
│   3. Pushes return value onto caller's stack                                │
│   4. Jumps back to saved return address                                     │
│                                                                              │
│   RET_VOID:                                                                  │
│       Same but doesn't push a return value                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Generate Return

```
function generateReturn(instr):
    if instr.value is not null:
        // Value already on stack from previous instruction
        emitByte(RET)
    else:
        emitByte(RET_VOID)
```

---

## Full Call Example

```
Source:
    fn square(x: i32) i32 {
        return x * x;
    }

    fn main() i32 {
        const result: i32 = square(5);
        return result;
    }

Function table:
    0: square (1 param, 0 locals)
    1: main   (0 params, 1 local)

Bytecode for square:
    LOAD_PARAM 0        ← push x
    LOAD_PARAM 0        ← push x again
    MUL_I32             ← x * x
    RET                 ← return result

Bytecode for main:
    PUSH_I32 5          ← argument for square
    CALL 0 1            ← call square with 1 arg
    STORE_LOCAL 0       ← store result
    LOAD_LOCAL 0        ← load result
    RET                 ← return it
```

---

## Nested Calls

```
Source:
    fn add(a: i32, b: i32) i32 { return a + b; }
    fn main() i32 { return add(add(1, 2), add(3, 4)); }

AIR for main:
    %0 = const_i32(1)
    %1 = const_i32(2)
    %2 = call("add", [%0, %1])     ← inner call 1
    %3 = const_i32(3)
    %4 = const_i32(4)
    %5 = call("add", [%3, %4])     ← inner call 2
    %6 = call("add", [%2, %5])     ← outer call
    %7 = ret(%6)

Bytecode for main:
    PUSH_I32 1
    PUSH_I32 2
    CALL 0 2            ← add(1,2) → returns 3
    PUSH_I32 3
    PUSH_I32 4
    CALL 0 2            ← add(3,4) → returns 7
    CALL 0 2            ← add(3,7) → returns 10
    RET

Stack trace:
    PUSH_I32 1   → [1]
    PUSH_I32 2   → [1][2]
    CALL 0 2     → [3]           ← result of add(1,2)
    PUSH_I32 3   → [3][3]
    PUSH_I32 4   → [3][3][4]
    CALL 0 2     → [3][7]        ← result of add(3,4)
    CALL 0 2     → [10]          ← result of add(3,7)
    RET          → returns 10
```

---

## Handling Function Indices

During codegen, we need to resolve function names to indices:

```
BytecodeGenerator:
    function_indices: Map<name, index>

    // First pass: collect all function names
    function collectFunctions(program):
        for fn_decl in program:
            function_indices[fn_decl.name] = function_indices.size

    // During codegen
    function getFunctionIndex(name) → index:
        return function_indices[name]
```

---

## Verify Your Implementation

### Test 1: Simple call
```
fn id(x: i32) i32 { return x; }
fn main() i32 { return id(42); }

main bytecode:
    PUSH_I32 42
    CALL 0 1
    RET
```

### Test 2: Two arguments
```
fn add(a: i32, b: i32) i32 { return a + b; }
fn main() i32 { return add(3, 5); }

main bytecode:
    PUSH_I32 3
    PUSH_I32 5
    CALL 0 2
    RET
```

### Test 3: Call result used in expression
```
fn double(x: i32) i32 { return x + x; }
fn main() i32 { return double(5) + 1; }

main bytecode:
    PUSH_I32 5
    CALL 0 1
    PUSH_I32 1
    ADD_I32
    RET
```

---

## What's Next

Now let's build the VM that executes this bytecode!

Next: [Lesson 5c.8: The VM Loop](../08-vm-loop/) →
