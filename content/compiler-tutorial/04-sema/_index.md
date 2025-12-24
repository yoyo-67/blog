---
title: "Section 4: Sema"
weight: 4
---

# Section 4: Sema (Semantic Analysis)

The parser checks structure. Sema checks meaning.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           WHAT SEMA DOES                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Parser accepts:              Sema rejects:                                 │
│                                                                              │
│   fn foo() i32 {               fn foo() i32 {                                │
│       return x;                    return x;    // x doesn't exist!          │
│   }                            }                                             │
│                                                                              │
│   fn bar() i32 {               fn bar() i32 {                                │
│       const x = 1;                 const x = 1;                              │
│       const x = 2;                 const x = 2; // x already declared!       │
│       return x;                    return x;                                 │
│   }                            }                                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What Sema Validates

1. **Names exist**: Is `x` actually declared?
2. **No duplicates**: Is `x` declared twice?
3. **Returns match**: Does return type match function signature?

---

## The Pipeline

```
Source Code
    │
    ▼
┌─────────┐
│  Lexer  │  → Tokens
└────┬────┘
     │
     ▼
┌─────────┐
│ Parser  │  → AST
└────┬────┘
     │
     ▼
┌─────────┐
│   ZIR   │  → Instructions (untyped)
└────┬────┘
     │
     ▼
┌─────────┐
│  SEMA   │  → Errors           ← WE ARE HERE
└─────────┘
```

---

## Lessons in This Section

| Lesson | Topic | What You'll Learn |
|--------|-------|-------------------|
| [1. What is Sema?](01-what-is-sema/) | Overview | What sema validates |
| [2. Pointer Chain](02-pointer-chain/) | Error locations | How errors point to source |
| [3. Tracking Names](03-tracking-names/) | Symbol table | Map names to types |
| [4. Undefined Variables](04-undefined-vars/) | Name checking | Detect missing declarations |
| [5. Duplicate Declarations](05-duplicate-decls/) | Uniqueness | Prevent re-declarations |
| [6. Return Type Declaration](06-return-type-decl/) | Syntax | Add return type to functions |
| [7. Return Type Checking](07-return-type-check/) | Validation | Match return types |
| [8. Putting Together](08-putting-together/) | Integration | Complete analyzer |

---

## Error Output

Sema produces helpful error messages:

```
1:19: error: undefined variable "x"
fn foo() i32 { return x; }
                      ^

1:31: error: duplicate declaration "x"
fn foo() i32 { const x = 1; const x = 2; }
                                  ^

1:35: error: return type mismatch: expected i32, got i64
fn foo(n: i64) i32 { return n; }
                            ^
```

---

## What You'll Build

By the end of this section, your analyzer will:

- Detect undefined variables
- Detect duplicate declarations
- Check return types match
- Report errors with source locations

---

## Start Here

Begin with [Lesson 1: What is Sema?](01-what-is-sema/) →
