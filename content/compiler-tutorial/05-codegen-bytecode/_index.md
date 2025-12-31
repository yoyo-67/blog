---
title: "Section 5c: Bytecode Backend"
weight: 9
---

# Section 5c: Bytecode Generation

An alternative backend that generates bytecode for a virtual machine.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       BYTECODE BACKEND PIPELINE                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR (Typed IR)                                                             │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────┐                                                       │
│   │ Bytecode Codegen│  Generate bytecode instructions                       │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │   program.bc    │  Binary bytecode format                               │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │  Virtual Machine│  Execute bytecode                                     │
│   └─────────────────┘                                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Bytecode?

Instead of generating machine code or C, we can generate bytecode:

- **Portable** - Same bytecode runs on any platform with the VM
- **Simple codegen** - Stack machines are easier than register allocation
- **Safe** - VM can enforce bounds, prevent crashes
- **Educational** - You understand every instruction that runs

Real-world examples: Java (JVM), Python, Lua, WebAssembly.

---

## Stack-Based vs Register-Based

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        VM ARCHITECTURES                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   STACK-BASED (we'll build this):      REGISTER-BASED:                      │
│                                                                              │
│   PUSH 3                               LOAD R0, 3                            │
│   PUSH 5                               LOAD R1, 5                            │
│   ADD          ← implicit operands     ADD R2, R0, R1  ← explicit operands  │
│                                                                              │
│   + Simpler instruction format         + Fewer instructions                  │
│   + Easier to generate                 + Better for optimization             │
│   - More instructions                  - More complex encoding               │
│                                                                              │
│   Examples: JVM, Python                Examples: Lua 5, Dalvik               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

We'll build a stack-based VM because it's simpler to generate code for.

---

## The Output

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

Becomes bytecode:

```
function add:
    LOAD_PARAM 0     ; push a onto stack
    LOAD_PARAM 1     ; push b onto stack
    ADD_I32          ; pop both, push result
    RET              ; return top of stack
```

Then a VM executes this bytecode instruction by instruction.

---

## Lessons in This Section

| Lesson | Topic | What You'll Learn |
|--------|-------|-------------------|
| [1. Why Bytecode](01-why-bytecode/) | Motivation | VMs, interpreters, tradeoffs |
| [2. Bytecode Format](02-bytecode-format/) | Opcodes | Instruction set design |
| [3. Stack Basics](03-stack-basics/) | Stack machine | Push, pop, stack state |
| [4. Constants](04-gen-constants/) | PUSH | Generate constant instructions |
| [5. Arithmetic](05-gen-arithmetic/) | ADD, SUB, ... | Generate arithmetic ops |
| [6. Functions](06-gen-functions/) | Frames | Locals, parameters, scopes |
| [7. Calls](07-gen-calls/) | CALL, RET | Function calls and returns |
| [8. VM Loop](08-vm-loop/) | Execution | The fetch-decode-execute loop |
| [9. Complete](09-putting-together/) | Integration | Full bytecode generator + VM |

---

## Prerequisites

Complete the main tutorial through Section 4 (Sema) first. This section provides an alternative to Section 5 (C Codegen).

---

## Start Here

Begin with [Lesson 1: Why Bytecode](01-why-bytecode/) →
