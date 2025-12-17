---
title: "Section 3: ZIR"
weight: 3
---

# Section 3: ZIR (Untyped Intermediate Representation)

The ZIR transforms tree structures into flat, linear instructions.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           WHAT ZIR DOES                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AST (tree):                     ZIR (linear):                             │
│                                                                              │
│        +                          %0 = constant(3)                          │
│       / \                         %1 = constant(5)                          │
│      3   5                        %2 = add(%0, %1)                          │
│                                                                              │
│   Tree is nested.                 Instructions are sequential.              │
│   Hard to analyze.                Easy to walk through.                     │
│   Node order unclear.             Clear execution order.                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why IR?

1. **Simpler to analyze**: Each instruction does one thing
2. **Explicit ordering**: No ambiguity about what happens first
3. **Easier code generation**: Maps directly to assembly/bytecode
4. **Enables optimization**: Patterns are easier to spot

---

## Why "Untyped"?

ZIR doesn't resolve types yet. It just references names as strings:

```
const x: i32 = 5;
return x;

ZIR:
%0 = constant(5)
%1 = decl("x", %0)        // Name "x" as string
%2 = ref("x")              // Reference "x" by name
%3 = ret(%2)
```

Type checking and name resolution happen in the next stage (Sema).

---

## Lessons in This Section

| Lesson | Topic | What You'll Add |
|--------|-------|-----------------|
| [1. IR Instructions](01-ir-instructions/) | Instruction types | Define ZIR instruction set |
| [2. Flatten Expressions](02-flatten-expr/) | Simple flattening | `a + b` → linear form |
| [3. Nested Expressions](03-flatten-nested/) | Complex flattening | `a + b * c` with precedence |
| [4. Name References](04-name-references/) | Variable refs | `decl_ref("x")` instructions |
| [5. Parameter References](05-param-references/) | Function params | `param_ref(0)` instructions |
| [6. Function IR](06-function-ir/) | Function structure | Full function in IR |
| [7. Complete ZIR](07-putting-together/) | Integration | Full ZIR generator |

---

## What You'll Build

By the end of this section, you can transform:

```
fn add(a: i32, b: i32) i32 {
    const result: i32 = a + b;
    return result;
}
```

Into:

```
function "add":
  params: [("a", i32), ("b", i32)]
  return_type: i32
  body:
    %0 = param_ref(0)           // a
    %1 = param_ref(1)           // b
    %2 = add(%0, %1)
    %3 = decl("result", %2)
    %4 = decl_ref("result")
    %5 = ret(%4)
```

---

## IR Design Philosophy

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        IR DESIGN PRINCIPLES                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. ONE instruction = ONE operation                                        │
│      Not: %0 = add(3, mul(4, 5))                                           │
│      Yes: %0 = const(4)                                                     │
│           %1 = const(5)                                                     │
│           %2 = mul(%0, %1)                                                  │
│           %3 = const(3)                                                     │
│           %4 = add(%3, %2)                                                  │
│                                                                              │
│   2. Results are numbered (%0, %1, %2, ...)                                 │
│      Each instruction produces a value.                                     │
│      That value has a unique number.                                        │
│                                                                              │
│   3. Order matters                                                          │
│      Instructions execute top-to-bottom.                                    │
│      Can only reference earlier results.                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Start Here

Begin with [Lesson 1: IR Instructions](01-ir-instructions/) →
