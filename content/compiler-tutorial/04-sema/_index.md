---
title: "Section 4: Sema"
weight: 4
---

# Section 4: Sema (Semantic Analysis)

Sema validates your program and resolves all names and types.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           WHAT SEMA DOES                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ZIR (untyped):                  AIR (typed):                              │
│                                                                              │
│   %0 = decl_ref("x")              %0 = local_get(slot: 0, type: i32)       │
│   %1 = param_ref(1)               %1 = param_get(index: 1, type: i32)      │
│   %2 = add(%0, %1)                %2 = add_i32(%0, %1)                      │
│                                                                              │
│   Names are strings              Names are resolved to locations            │
│   Types are unknown               Types are verified and explicit           │
│   Errors not caught               Errors caught and reported                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What Sema Validates

1. **Names exist**: Is `x` actually declared?
2. **Types match**: Can you add `i32 + i32`?
3. **Returns are correct**: Does return type match function signature?
4. **No duplicates**: Is `x` declared twice in the same scope?

---

## ZIR → AIR

```
ZIR: Untyped IR with string names
AIR: Typed IR with resolved references

ZIR:
    %0 = decl_ref("x")       // Who is "x"?

AIR:
    %0 = local_get(0)        // Local variable slot 0
    // Or
    %0 = param_get(1)        // Parameter index 1
```

---

## Lessons in This Section

| Lesson | Topic | What You'll Add |
|--------|-------|-----------------|
| [1. Type System](01-type-system/) | Types | Define i32, i64, bool, void |
| [2. Type of Expression](02-type-of-expr/) | Inference | What type is `3 + 5`? |
| [3. Symbol Table](03-symbol-table/) | Tracking | Map names to declarations |
| [4. Resolve Names](04-resolve-names/) | Lookup | `decl_ref("x")` → actual location |
| [5. Type Check](05-type-check/) | Validation | Verify types match |
| [6. AIR Output](06-air-output/) | Generation | Produce typed instructions |
| [7. Error Handling](07-error-handling/) | Errors | Report meaningful messages |
| [8. Complete Sema](08-putting-together/) | Integration | Full semantic analyzer |

---

## What You'll Build

By the end of this section, you can transform:

```
ZIR:
  function "add":
    params: [("a", i32), ("b", i32)]
    %0 = param_ref(0)
    %1 = param_ref(1)
    %2 = add(%0, %1)
    %3 = ret(%2)
```

Into:

```
AIR:
  function "add":
    params: [i32, i32]
    return_type: i32
    %0 = param_get(0)     // type: i32
    %1 = param_get(1)     // type: i32
    %2 = add_i32(%0, %1)  // type: i32
    %3 = ret(%2)
```

---

## Error Detection

Sema catches errors like:

```
fn foo() i32 {
    return x;        // Error: undefined variable 'x'
}

fn bar() i32 {
    const x: i32 = 5;
    const x: i32 = 6;   // Error: 'x' already declared
    return x;
}

fn baz(a: i32, b: bool) i32 {
    return a + b;    // Error: cannot add i32 and bool
}
```

---

## Start Here

Begin with [Lesson 1: Type System](01-type-system/) →
