---
title: "1.5: Dot Notation"
weight: 5
---

# Lesson 1.5: Dot Notation

Let's add the clean `namespace.function()` syntax instead of writing `namespace_function()`.

---

## Goal

Transform `math.add(1, 2)` into a call to `math_add(1, 2)` during parsing.

---

## The Transformation

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         DOT NOTATION TRANSFORMATION                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source code:          math.add(1, 2)                                       │
│                          │   │                                               │
│                          │   └── function name                               │
│                          └── namespace                                       │
│                                                                              │
│   Tokens:               [math] [.] [add] [(] [1] [,] [2] [)]                │
│                                                                              │
│   After parsing:        FnCall { name: "math_add", args: [1, 2] }           │
│                                                                              │
│   The dot is just syntactic sugar - we combine the names at parse time.     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Add Dot Token

Add a new token type for the dot:

```
// In token types
TokenType = enum {
    // ... existing tokens ...
    dot,           // .
}

// In character map
char_type_map = {
    '.': dot,
    // ... existing mappings ...
}
```

---

## Step 2: Update parsePrimary

When we see an identifier, check if it's followed by a dot:

```
parsePrimary(allocator) -> Node {
    // ... existing code for lparen, numbers, etc ...

    if see(identifier) {
        token = consume()  // e.g., "math"

        // NEW: Check for namespace.function() syntax
        if see(dot) {
            consume()  // eat the dot
            fn_token = expect(identifier)  // e.g., "add"

            // Combine: "math" + "_" + "add" = "math_add"
            combined_name = format("{}_{}", token.lexeme, fn_token.lexeme)

            if see(lparen) {
                return parseFnCallWithName(allocator, combined_name, token)
            }

            // Could also be a namespaced variable reference
            return Node.identifier_ref { name: combined_name, token: token }
        }

        // Regular function call or identifier
        if see(lparen) {
            return parseFnCall(allocator, token)
        }

        return Node.identifier_ref { name: token.lexeme, token: token }
    }

    // ... rest of parsePrimary ...
}
```

---

## Step 3: Add parseFnCallWithName Helper

Refactor function call parsing to accept a pre-built name:

```
// Original - takes token and uses its lexeme
parseFnCall(allocator, name_token) -> Node {
    return parseFnCallWithName(allocator, name_token.lexeme, name_token)
}

// New - takes explicit name
parseFnCallWithName(allocator, name, token) -> Node {
    expect(lparen)
    args = []

    if not see(rparen) {
        while true {
            arg = parseExpression(allocator)
            args.append(arg)
            if not see(comma) { break }
            consume()  // eat comma
        }
    }

    expect(rparen)

    return Node.fn_call {
        name: name,      // Use the provided name
        args: args,
        token: token,
    }
}
```

---

## Why This Works

Both sides use the same naming convention:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         MATCHING NAMES                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   CALLER (parser)                    CALLEE (codegen)                        │
│   ────────────────                   ────────────────                        │
│                                                                              │
│   math.add(1, 2)                     import "math.mini" as math              │
│       │                                  │                                   │
│       ▼                                  ▼                                   │
│   "math" + "_" + "add"               "math" + "_" + "add"                    │
│       │                                  │                                   │
│       ▼                                  ▼                                   │
│   calls "math_add"        ═══════    defines "math_add"                      │
│                                                                              │
│   THEY MATCH! The call resolves correctly.                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Example

```
// math.mini
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn square(n: i32) i32 {
    return n * n;
}

// main.mini
import "math.mini" as math;

fn main() i32 {
    const x = math.add(10, 5);    // Becomes: math_add(10, 5)
    const y = math.square(x);     // Becomes: math_square(x)
    return y;                      // Returns 225
}
```

After compilation:
- `math.add` → calls `math_add` ✓
- `math.square` → calls `math_square` ✓
- Result: 225 (15 squared)

---

## Verify Your Implementation

### Test 1: Dot notation parsing
```
Input:  math.add(1, 2)
Tokens: [identifier:"math"] [dot:"."] [identifier:"add"] [lparen] [integer:1] ...
Output: FnCall { name: "math_add", args: [1, 2] }
```

### Test 2: Full compilation
```
// main.mini
import "math.mini" as math;
fn main() i32 { return math.add(10, 5); }

// math.mini
fn add(a: i32, b: i32) i32 { return a + b; }

Run: ./compiler main.mini
Expected exit code: 15
```

### Test 3: Multiple namespaces
```
import "math.mini" as m;
import "utils.mini" as u;

fn main() i32 {
    const a = m.add(1, 2);
    const b = u.double(a);
    return b;
}

Check: m.add → m_add
       u.double → u_double
```

---

## Summary

You've built a complete import system:

1. **CompilationUnit** - Represents a source file
2. **Import parsing** - `import "file" as namespace;`
3. **Recursive loading** - Load imported files and their imports
4. **Namespace prefixing** - `add` → `math_add`
5. **Dot notation** - `math.add()` → `math_add()`

---

## What's Next

Now let's make compilation faster with caching.

Next: [Section 2: Incremental Compilation](../../02-incremental-compilation/) →
