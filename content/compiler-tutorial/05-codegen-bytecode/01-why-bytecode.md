---
title: "5c.1: Why Bytecode"
weight: 1
---

# Lesson 5c.1: Why Bytecode?

Understanding virtual machines and bytecode compilation.

---

## Goal

Understand what bytecode is, how it differs from native code, and why we might choose this approach.

---

## What is Bytecode?

Bytecode is a set of instructions designed for a virtual machine, not a real CPU.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         BYTECODE vs NATIVE CODE                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source Code                                                                │
│       │                                                                      │
│       ├─────────────────────┬─────────────────────┐                         │
│       ▼                     ▼                     ▼                         │
│   ┌─────────┐         ┌─────────┐          ┌─────────┐                     │
│   │ Native  │         │Bytecode │          │   C     │                     │
│   │  Code   │         │         │          │  Code   │                     │
│   └────┬────┘         └────┬────┘          └────┬────┘                     │
│        │                   │                    │                           │
│        ▼                   ▼                    ▼                           │
│   ┌─────────┐         ┌─────────┐          ┌─────────┐                     │
│   │   CPU   │         │   VM    │          │   gcc   │                     │
│   └─────────┘         └─────────┘          └─────────┘                     │
│                                                                              │
│   Direct execution    Software interprets   Another compiler               │
│   Fastest, complex    Portable, simple      Leverages existing              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What is a Virtual Machine?

A virtual machine (VM) is a program that executes bytecode. It simulates a computer:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           VIRTUAL MACHINE                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   A VM has:                                                                  │
│                                                                              │
│   • Instruction Pointer (IP) - which instruction to execute next            │
│   • Stack - for operands and intermediate values                            │
│   • Memory - for variables and data                                         │
│   • Opcodes - the instruction set it understands                            │
│                                                                              │
│   The VM loop:                                                               │
│                                                                              │
│   while running:                                                             │
│       instruction = bytecode[IP]                                            │
│       IP = IP + 1                                                           │
│       execute(instruction)                                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## VM vs Interpreter

These terms are often confused:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      INTERPRETER vs VIRTUAL MACHINE                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   TREE-WALKING INTERPRETER:           BYTECODE VM:                          │
│                                                                              │
│   Source → AST → Walk & Execute       Source → AST → Bytecode → Execute    │
│                                                                              │
│   evaluate(node):                     run():                                 │
│     if node is Add:                     opcode = fetch()                    │
│       left = evaluate(node.left)        switch opcode:                      │
│       right = evaluate(node.right)        ADD: push(pop() + pop())          │
│       return left + right                 ...                               │
│                                                                              │
│   Pros:                               Pros:                                  │
│   - Simple to implement               - Faster (no tree traversal)          │
│   - Good for simple languages         - Compact representation              │
│                                        - Can save/load bytecode             │
│   Cons:                                                                      │
│   - Slow (tree traversal)             Cons:                                  │
│   - Memory overhead of AST            - More implementation work             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

A bytecode VM **is** an interpreter - it interprets bytecode instructions.

---

## Tradeoffs

| Approach | Execution Speed | Compile Complexity | Portability |
|----------|-----------------|-------------------|-------------|
| Native code | Fastest | High | Low (platform-specific) |
| Bytecode + VM | Medium | Low | High (VM on each platform) |
| Tree interpreter | Slowest | Lowest | High |

---

## Why Choose Bytecode?

For our compiler, bytecode is attractive because:

1. **Simple codegen** - Stack machines need no register allocation
2. **Portable** - Write VM once, run bytecode anywhere
3. **Educational** - You control and understand every instruction
4. **Debuggable** - Easy to trace execution

---

## Real-World Examples

| Language | VM | Notes |
|----------|-----|-------|
| Java | JVM | Stack-based, JIT compiled |
| Python | CPython | Stack-based, interpreted |
| Lua | Lua VM | Register-based, very fast |
| C# | CLR | Stack-based, JIT compiled |
| WebAssembly | Browser | Stack-based, near-native speed |

---

## Our Approach

We'll build:

1. **Bytecode Generator** - Converts AIR to bytecode instructions
2. **Virtual Machine** - Executes the bytecode

```
Source → Lexer → Parser → ZIR → Sema → AIR → Bytecode → VM
                                              ↑         ↑
                                         We build   We build
                                          this       this
```

---

## Verify Your Understanding

### Question 1
What's the main advantage of bytecode over native machine code?

Answer: Portability. The same bytecode runs on any platform that has the VM, while native code only runs on one specific CPU architecture.

### Question 2
Why is a bytecode VM faster than a tree-walking interpreter?

Answer: Bytecode is a compact, linear representation. No tree traversal, no recursive function calls for each node, and better cache locality.

### Question 3
What does a VM need to execute bytecode?

Answer: An instruction pointer (IP), a stack (for stack-based VMs), memory for variables, and a loop that fetches and executes instructions.

---

## What's Next

Let's design our bytecode instruction set.

Next: [Lesson 5c.2: Bytecode Format](../02-bytecode-format/) →
