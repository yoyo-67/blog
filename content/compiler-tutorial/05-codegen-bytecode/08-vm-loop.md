---
title: "5c.8: The VM Loop"
weight: 8
---

# Lesson 5c.8: The VM Loop

Build the virtual machine that executes bytecode.

---

## Goal

Implement the fetch-decode-execute loop that runs bytecode.

---

## VM Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          VM STRUCTURE                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   VM:                                                                        │
│       code: ByteArray              // The bytecode                          │
│       ip: integer                  // Instruction pointer                   │
│                                                                              │
│       stack: Array[Value]          // Operand stack                         │
│       sp: integer                  // Stack pointer                         │
│                                                                              │
│       call_stack: Array[Frame]     // Call frames                           │
│       fp: integer                  // Frame pointer                         │
│                                                                              │
│       functions: FunctionTable     // Function metadata                     │
│                                                                              │
│   Frame:                                                                     │
│       return_ip: integer           // Where to return to                    │
│       base_sp: integer             // Stack base for this frame            │
│       function: FunctionEntry      // Which function                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Main Loop

```
function run() → Value:
    while true:
        opcode = readByte()

        switch opcode:
            PUSH_I32:
                value = readI32()
                push(value)

            PUSH_I64:
                value = readI64()
                push(value)

            PUSH_BOOL:
                value = readByte()
                push(value)

            ADD_I32:
                b = pop()
                a = pop()
                push(a + b)

            SUB_I32:
                b = pop()
                a = pop()
                push(a - b)

            // ... more cases

            RET:
                result = pop()
                if no more frames:
                    return result
                else:
                    returnFromCall()
                    push(result)

            HALT:
                return pop()
```

---

## Reading Bytes

```
function readByte() → byte:
    b = code[ip]
    ip = ip + 1
    return b

function readI32() → i32:
    // Little-endian: read 4 bytes
    b0 = readByte()
    b1 = readByte()
    b2 = readByte()
    b3 = readByte()
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)

function readU16() → u16:
    b0 = readByte()
    b1 = readByte()
    return b0 | (b1 << 8)
```

---

## Stack Operations

```
function push(value):
    stack[sp] = value
    sp = sp + 1

function pop() → Value:
    sp = sp - 1
    return stack[sp]

function peek() → Value:
    return stack[sp - 1]
```

---

## Parameter and Local Access

Parameters and locals are stored in the stack frame:

```
function loadParam(index) → Value:
    frame = call_stack[fp - 1]
    return stack[frame.base_sp + index]

function loadLocal(index) → Value:
    frame = call_stack[fp - 1]
    local_start = frame.base_sp + frame.function.num_params
    return stack[local_start + index]

function storeLocal(index, value):
    frame = call_stack[fp - 1]
    local_start = frame.base_sp + frame.function.num_params
    stack[local_start + index] = value
```

---

## Handling Calls

```
function executeCall(fn_index, arg_count):
    // Get function metadata
    func = functions[fn_index]

    // Create new frame
    frame = new Frame()
    frame.return_ip = ip                  // Save where to return
    frame.base_sp = sp - arg_count        // Args are already on stack
    frame.function = func

    // Push frame
    call_stack[fp] = frame
    fp = fp + 1

    // Allocate space for locals
    for i in 0..func.num_locals:
        push(0)  // Initialize locals to 0

    // Jump to function code
    ip = func.code_offset

function returnFromCall():
    // Pop frame
    fp = fp - 1
    frame = call_stack[fp]

    // Restore stack (discard args + locals)
    sp = frame.base_sp

    // Return to caller
    ip = frame.return_ip
```

---

## Complete VM Loop

```
function run() → Value:
    while true:
        opcode = readByte()

        switch opcode:
            // Constants
            PUSH_I32:    push(readI32())
            PUSH_I64:    push(readI64())
            PUSH_BOOL:   push(readByte())

            // Arithmetic
            ADD_I32:     b = pop(); a = pop(); push(a + b)
            SUB_I32:     b = pop(); a = pop(); push(a - b)
            MUL_I32:     b = pop(); a = pop(); push(a * b)
            DIV_I32:     b = pop(); a = pop(); push(a / b)
            NEG_I32:     a = pop(); push(-a)

            // 64-bit arithmetic (same pattern)
            ADD_I64:     b = pop(); a = pop(); push(a + b)
            // ...

            // Variables
            LOAD_PARAM:  push(loadParam(readByte()))
            LOAD_LOCAL:  push(loadLocal(readByte()))
            STORE_LOCAL: storeLocal(readByte(), pop())

            // Control flow
            CALL:
                fn_index = readU16()
                arg_count = readByte()
                executeCall(fn_index, arg_count)

            RET:
                result = pop()
                if fp == 0:
                    return result  // Exit program
                returnFromCall()
                push(result)

            RET_VOID:
                if fp == 0:
                    return 0
                returnFromCall()

            // Other
            POP:         pop()
            HALT:        return pop()
```

---

## Execution Trace

Let's trace `add(3, 5)`:

```
Code:
    ; main
    PUSH_I32 3
    PUSH_I32 5
    CALL 0 2
    RET

    ; add (at offset 12)
    LOAD_PARAM 0
    LOAD_PARAM 1
    ADD_I32
    RET

Trace:

ip=0  PUSH_I32 3     stack: [3]           frames: []
ip=5  PUSH_I32 5     stack: [3][5]        frames: []
ip=10 CALL 0 2       stack: [3][5]        frames: [main@ip=13]
                     → jump to add
ip=12 LOAD_PARAM 0   stack: [3][5][3]     frames: [main@ip=13]
ip=14 LOAD_PARAM 1   stack: [3][5][3][5]  frames: [main@ip=13]
ip=16 ADD_I32        stack: [3][5][8]     frames: [main@ip=13]
ip=17 RET            stack: [8]           frames: []
                     → return to main
ip=13 RET            returns 8
```

---

## Error Handling

The VM should handle errors:

```
function run() → Result:
    try:
        // ... main loop ...

    catch StackUnderflow:
        return Error("Stack underflow")

    catch StackOverflow:
        return Error("Stack overflow")

    catch InvalidOpcode:
        return Error("Unknown opcode")

    catch DivisionByZero:
        return Error("Division by zero")
```

---

## Verify Your Implementation

### Test 1: Simple constant
```
Bytecode:
    PUSH_I32 42
    HALT

Expected: returns 42
```

### Test 2: Arithmetic
```
Bytecode:
    PUSH_I32 10
    PUSH_I32 3
    SUB_I32
    HALT

Expected: returns 7
```

### Test 3: Function call
```
Bytecode:
    ; main
    PUSH_I32 3
    PUSH_I32 5
    CALL 0 2
    HALT

    ; add (function 0)
    LOAD_PARAM 0
    LOAD_PARAM 1
    ADD_I32
    RET

Expected: returns 8
```

---

## What's Next

Let's put everything together into a complete implementation.

Next: [Lesson 5c.9: Putting It Together](../09-putting-together/) →
