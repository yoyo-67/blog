---
title: "5c.9: Putting It Together"
weight: 9
---

# Lesson 5c.9: Putting It Together

The complete bytecode generator and virtual machine.

---

## Goal

Combine all the pieces into a working bytecode backend.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       COMPLETE SYSTEM                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source                                                                     │
│     │                                                                        │
│     ▼                                                                        │
│   [Lexer] → [Parser] → [ZIR Gen] → [Sema] → [AIR]                          │
│                                                │                             │
│                                                ▼                             │
│                                   ┌────────────────────┐                    │
│                                   │ Bytecode Generator │                    │
│                                   └─────────┬──────────┘                    │
│                                             │                                │
│                                             ▼                                │
│                                   ┌────────────────────┐                    │
│                                   │  Program (bytes)   │                    │
│                                   │  + Function Table  │                    │
│                                   └─────────┬──────────┘                    │
│                                             │                                │
│                                             ▼                                │
│                                   ┌────────────────────┐                    │
│                                   │  Virtual Machine   │                    │
│                                   └─────────┬──────────┘                    │
│                                             │                                │
│                                             ▼                                │
│                                          Result                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Opcode Definitions

```
// Opcode values
PUSH_I32    = 0x01
PUSH_I64    = 0x02
PUSH_BOOL   = 0x03

ADD_I32     = 0x10
SUB_I32     = 0x11
MUL_I32     = 0x12
DIV_I32     = 0x13
NEG_I32     = 0x14

ADD_I64     = 0x18
SUB_I64     = 0x19
MUL_I64     = 0x1A
DIV_I64     = 0x1B
NEG_I64     = 0x1C

LOAD_PARAM  = 0x20
LOAD_LOCAL  = 0x21
STORE_LOCAL = 0x22

CALL        = 0x30
RET         = 0x31
RET_VOID    = 0x32

POP         = 0x40
HALT        = 0xFF
```

---

## Data Structures

```
FunctionEntry:
    name: string
    num_params: integer
    num_locals: integer
    code_offset: integer
    code_length: integer

Program:
    functions: Array[FunctionEntry]
    code: ByteArray
    entry_point: integer  // main function index

Frame:
    return_ip: integer
    base_sp: integer
    function: FunctionEntry
```

---

## Bytecode Generator

```
BytecodeGenerator:
    output: ByteArray
    functions: Array[FunctionEntry]
    function_indices: Map[string, integer]
    current_function: FunctionEntry
    local_indices: Map[string, integer]
    next_local: integer

    function generate(air_program) → Program:
        // First pass: collect function names
        for decl in air_program:
            if decl is function:
                function_indices[decl.name] = functions.length
                functions.append(empty FunctionEntry)

        // Second pass: generate code for each function
        for decl in air_program:
            if decl is function:
                generateFunction(decl)

        return Program(functions, output, getEntryPoint())

    function generateFunction(fn_decl):
        index = function_indices[fn_decl.name]
        entry = functions[index]
        entry.name = fn_decl.name
        entry.num_params = fn_decl.params.length
        entry.code_offset = output.length

        local_indices.clear()
        next_local = 0

        for instr in fn_decl.body:
            generateInstruction(instr)

        entry.num_locals = next_local
        entry.code_length = output.length - entry.code_offset

    function generateInstruction(instr):
        switch instr.type:
            const_int:
                if instr.bits == 32:
                    emitByte(PUSH_I32)
                    emitI32(instr.value)
                else:
                    emitByte(PUSH_I64)
                    emitI64(instr.value)

            const_bool:
                emitByte(PUSH_BOOL)
                emitByte(instr.value ? 1 : 0)

            add:
                emitByte(instr.bits == 32 ? ADD_I32 : ADD_I64)

            sub:
                emitByte(instr.bits == 32 ? SUB_I32 : SUB_I64)

            mul:
                emitByte(instr.bits == 32 ? MUL_I32 : MUL_I64)

            div:
                emitByte(instr.bits == 32 ? DIV_I32 : DIV_I64)

            neg:
                emitByte(instr.bits == 32 ? NEG_I32 : NEG_I64)

            param:
                emitByte(LOAD_PARAM)
                emitByte(instr.index)

            decl_const, decl_var:
                local_indices[instr.name] = next_local
                emitByte(STORE_LOCAL)
                emitByte(next_local)
                next_local = next_local + 1

            load:
                idx = local_indices[instr.name]
                emitByte(LOAD_LOCAL)
                emitByte(idx)

            call:
                fn_idx = function_indices[instr.callee]
                emitByte(CALL)
                emitU16(fn_idx)
                emitByte(instr.args.length)

            ret:
                if instr.has_value:
                    emitByte(RET)
                else:
                    emitByte(RET_VOID)

    function getEntryPoint() → integer:
        return function_indices["main"]
```

---

## Virtual Machine

```
VM:
    code: ByteArray
    ip: integer

    stack: Array[Value]
    sp: integer

    call_stack: Array[Frame]
    fp: integer

    functions: Array[FunctionEntry]

    function init(program):
        code = program.code
        functions = program.functions
        ip = functions[program.entry_point].code_offset
        sp = 0
        fp = 0

    function run() → Value:
        while true:
            opcode = readByte()

            switch opcode:
                PUSH_I32:    push(readI32())
                PUSH_I64:    push(readI64())
                PUSH_BOOL:   push(readByte())

                ADD_I32, ADD_I64:
                    b = pop(); a = pop(); push(a + b)
                SUB_I32, SUB_I64:
                    b = pop(); a = pop(); push(a - b)
                MUL_I32, MUL_I64:
                    b = pop(); a = pop(); push(a * b)
                DIV_I32, DIV_I64:
                    b = pop(); a = pop(); push(a / b)
                NEG_I32, NEG_I64:
                    push(-pop())

                LOAD_PARAM:
                    idx = readByte()
                    push(getParam(idx))
                LOAD_LOCAL:
                    idx = readByte()
                    push(getLocal(idx))
                STORE_LOCAL:
                    idx = readByte()
                    setLocal(idx, pop())

                CALL:
                    fn_idx = readU16()
                    argc = readByte()
                    doCall(fn_idx, argc)
                RET:
                    result = pop()
                    if fp == 0:
                        return result
                    doReturn()
                    push(result)
                RET_VOID:
                    if fp == 0:
                        return 0
                    doReturn()

                POP:
                    pop()
                HALT:
                    return pop()

    function doCall(fn_idx, argc):
        func = functions[fn_idx]
        frame = Frame()
        frame.return_ip = ip
        frame.base_sp = sp - argc
        frame.function = func
        call_stack[fp] = frame
        fp = fp + 1
        // Reserve space for locals
        for i in 0..func.num_locals:
            push(0)
        ip = func.code_offset

    function doReturn():
        fp = fp - 1
        frame = call_stack[fp]
        sp = frame.base_sp
        ip = frame.return_ip

    function getParam(idx) → Value:
        return stack[call_stack[fp-1].base_sp + idx]

    function getLocal(idx) → Value:
        frame = call_stack[fp-1]
        return stack[frame.base_sp + frame.function.num_params + idx]

    function setLocal(idx, value):
        frame = call_stack[fp-1]
        stack[frame.base_sp + frame.function.num_params + idx] = value
```

---

## Running a Program

```
function compile_and_run(source) → Value:
    // Frontend (same as before)
    tokens = lex(source)
    ast = parse(tokens)
    zir = generateZIR(ast)
    air = analyze(zir)

    // Backend: bytecode
    generator = BytecodeGenerator()
    program = generator.generate(air)

    // Execute
    vm = VM()
    vm.init(program)
    return vm.run()
```

---

## Complete Example

```
Source:
    fn add(a: i32, b: i32) i32 {
        return a + b;
    }

    fn main() i32 {
        const x: i32 = 3;
        const y: i32 = 5;
        return add(x, y);
    }

Generated bytecode:

Function table:
    0: add  (2 params, 0 locals, offset 0)
    1: main (0 params, 2 locals, offset 4)

Code (hex):
    ; add
    20 00           LOAD_PARAM 0
    20 01           LOAD_PARAM 1
    10              ADD_I32
    31              RET

    ; main
    01 03 00 00 00  PUSH_I32 3
    22 00           STORE_LOCAL 0
    01 05 00 00 00  PUSH_I32 5
    22 01           STORE_LOCAL 1
    21 00           LOAD_LOCAL 0
    21 01           LOAD_LOCAL 1
    30 00 00 02     CALL 0 2
    31              RET

Execution:
    1. VM starts at main (offset 4)
    2. Pushes 3, stores in local 0
    3. Pushes 5, stores in local 1
    4. Loads local 0 (3), loads local 1 (5)
    5. Calls add with 2 args
    6. add: loads params, adds, returns 8
    7. main: returns 8

Result: 8
```

---

## Debugging: Disassembler

Build a disassembler to inspect bytecode:

```
function disassemble(program):
    for func in program.functions:
        print("function " + func.name + ":")
        ip = func.code_offset
        end = ip + func.code_length

        while ip < end:
            print("  " + formatAddress(ip) + ": ")
            opcode = code[ip]
            ip = ip + 1

            switch opcode:
                PUSH_I32:
                    val = readI32AtOffset(ip)
                    print("PUSH_I32 " + val)
                    ip = ip + 4
                ADD_I32:
                    print("ADD_I32")
                // ... etc
```

---

## Extensions

Ideas to extend the bytecode VM:

1. **Comparisons**: Add `LT`, `GT`, `EQ` opcodes
2. **Jumps**: Add `JUMP`, `JUMP_IF_FALSE` for conditionals and loops
3. **Debug info**: Track source locations for error messages
4. **Optimization**: Peephole optimization on bytecode
5. **JIT**: Compile hot functions to machine code

---

## What You've Built

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        SUMMARY                                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   You've built:                                                              │
│                                                                              │
│   ✓ A bytecode instruction set with 20+ opcodes                             │
│   ✓ A bytecode generator that converts AIR to bytecode                      │
│   ✓ A stack-based virtual machine                                           │
│   ✓ Function calls with proper stack frames                                 │
│   ✓ Local variables and parameters                                          │
│                                                                              │
│   This is how real VMs work:                                                 │
│   - Python's CPython                                                        │
│   - Java's JVM                                                               │
│   - Lua's interpreter                                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Congratulations!

You've completed the bytecode backend tutorial. You now understand:

- What a virtual machine is and how it works
- How to design a bytecode instruction set
- How stack-based execution works
- How to generate bytecode from typed IR
- How to implement a VM execution loop

This is a foundation you can build on for more advanced features like garbage collection, just-in-time compilation, or debugging support.
