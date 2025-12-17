---
title: "Section 5: Codegen"
weight: 5
---

# Section 5: Code Generation

Transform AIR into executable output.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         WHAT CODEGEN DOES                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR:                            Output (C code):                          │
│                                                                              │
│   %0 = param_get(0)               int32_t p0 = ...;                         │
│   %1 = param_get(1)               int32_t p1 = ...;                         │
│   %2 = add_i32(%0, %1)            int32_t t2 = p0 + p1;                     │
│   %3 = ret(%2)                    return t2;                                │
│                                                                              │
│   We'll generate C code - it's readable and compiles everywhere!            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Generate C?

We could generate:
- **Machine code** (x86, ARM) - complex, platform-specific
- **LLVM IR** - powerful but adds dependency
- **Bytecode** - needs a VM
- **C code** - simple, portable, readable!

C is perfect for learning: you can see exactly what your compiler produces.

---

## The Output

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

Becomes:

```c
#include <stdint.h>

int32_t add(int32_t p0, int32_t p1) {
    int32_t t0 = p0 + p1;
    return t0;
}
```

---

## Lessons in This Section

| Lesson | Topic | What You'll Add |
|--------|-------|-----------------|
| [1. Target Choice](01-target-choice/) | Output format | Why C? Alternatives |
| [2. Type Mapping](02-type-mapping/) | Types | i32 → int32_t |
| [3. Constants](03-gen-constants/) | Literals | `int32_t t0 = 42;` |
| [4. Binary Ops](04-gen-binary/) | Arithmetic | `t2 = t0 + t1;` |
| [5. Variables](05-gen-variables/) | Locals | Local variable storage |
| [6. Functions](06-gen-functions/) | Signatures | Function declarations |
| [7. Return](07-gen-return/) | Returns | `return t0;` |
| [8. Calls](08-gen-calls/) | Calling | `foo(x, y)` |
| [9. Program](09-gen-program/) | Structure | Headers, main |
| [10. Complete](10-putting-together/) | Integration | Full code generator |

---

## What You'll Build

By the end of this section, you can transform:

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn main() i32 {
    return 0;
}
```

Into:

```c
#include <stdint.h>
#include <stdbool.h>

int32_t add(int32_t p0, int32_t p1) {
    int32_t t0 = p0 + p1;
    return t0;
}

int32_t main() {
    return 0;
}
```

Which compiles with any C compiler:
```bash
cc output.c -o program
./program
```

---

## Code Generation Strategy

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     CODEGEN STRATEGY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   For each AIR instruction, emit corresponding C code:                      │
│                                                                              │
│   const_i32(42)         →  int32_t tN = 42;                                │
│   param_get(0)          →  int32_t tN = p0;                                │
│   local_get(slot)       →  int32_t tN = local_slot;                        │
│   local_set(slot, val)  →  local_slot = tN;                                │
│   add_i32(a, b)         →  int32_t tN = tA + tB;                           │
│   ret(val)              →  return tN;                                       │
│                                                                              │
│   Each instruction result becomes a temporary variable: t0, t1, t2, ...    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Start Here

Begin with [Lesson 1: Target Choice](01-target-choice/) →
