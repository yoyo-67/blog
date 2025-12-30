---
title: "Module 5: Dot Notation"
weight: 5
---

# Module 5: Dot Notation

Functions are correctly prefixed as `math_add`, but users have to write `math_add(1, 2)` to call them. This module teaches you to add syntactic sugar so users can write `math.add(1, 2)` instead.

**What you'll build:**
- Understanding why we need dot notation
- Dot token in the lexer
- Updated `parsePrimary()` to handle `namespace.function`
- Name combination logic

---

## Sub-lesson 5.1: The Ugly Syntax Problem

### The Problem

After namespace prefixing, functions have names like `math_add`. But forcing users to write these prefixed names is ugly:

```
// What users have to write now:
import "math.mini" as math;

fn main() i32 {
    const x = math_add(10, 5);       // Ugly!
    const y = math_multiply(x, 2);   // Ugly!
    const z = utils_format(y);       // Ugly!
    return z;
}
```

This is bad for several reasons:
1. Users must remember the underscore convention
2. Doesn't look like an import system
3. No visual connection between `import ... as math` and `math_add`

### The Solution

Let users write `math.add(1, 2)` and transform it to `math_add(1, 2)` during parsing:

```
// What users WANT to write:
import "math.mini" as math;

fn main() i32 {
    const x = math.add(10, 5);       // Nice!
    const y = math.multiply(x, 2);   // Nice!
    const z = utils.format(y);       // Nice!
    return z;
}
```

**How It Works:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ DOT NOTATION TRANSFORMATION                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ User writes:      math.add(10, 5)                                   │
│                     │   │                                           │
│                     │   └── function name                           │
│                     └── namespace (from import)                     │
│                                                                     │
│ Parser transforms: math.add  →  math_add                            │
│                                                                     │
│ Final AST:        FnCall { name: "math_add", args: [10, 5] }       │
│                                                                     │
│ The dot is SYNTACTIC SUGAR - it's converted during parsing.         │
│ By the time we reach code generation, it's just math_add.           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Why Transform at Parse Time?**

We could:
1. **Parse time** (what we do): `math.add` → `math_add` immediately
2. **Later phase**: Keep `math.add` in AST, resolve during semantic analysis

Parse-time transformation is simpler:
- No new AST node type needed
- No resolution phase needed
- Code generation sees regular function calls

### What This Enables

Clean, readable import syntax:

```
import "graphics.mini" as gfx;
import "math.mini" as math;
import "io.mini" as io;

fn main() i32 {
    // Clear visual relationship between import and usage
    gfx.clear();
    const angle = math.radians(45);
    io.print(angle);
    return 0;
}
```

---

## Sub-lesson 5.2: Adding the Dot Token

### The Problem

The lexer doesn't recognize `.` as a token:

```
Input: math.add(1, 2)

Current lexer produces: [identifier:math] [ERROR: unknown char '.'] ...

We need:                [identifier:math] [dot:.] [identifier:add] ...
```

### The Solution

Add a dot token type and teach the lexer to recognize it.

**Token Type:**

```
TokenType = enum {
    // ... existing tokens ...

    dot,           // The '.' character
}
```

**Character Mapping:**

```
// In your lexer's character handling

nextToken(self) -> Token {
    // ... skip whitespace ...

    c = self.current()

    // Check for single-character tokens
    if c == '.' {
        return self.makeToken(dot)
    }

    if c == '(' {
        return self.makeToken(lparen)
    }

    // ... rest of lexer ...
}
```

**Alternative: Character Map:**

If your lexer uses a lookup table:

```
char_to_token = {
    '.': dot,
    '(': lparen,
    ')': rparen,
    ',': comma,
    ';': semicolon,
    // ... etc ...
}

nextToken(self) -> Token {
    c = self.current()

    if char_to_token.get(c) is token_type {
        return self.makeToken(token_type)
    }

    // ... handle identifiers, numbers, etc ...
}
```

### Try It Yourself

1. Add `dot` to your token types
2. Update lexer to recognize `.`
3. Test:

```
// Test: Single dot
tokens = lex(".")
assert tokens[0].type == dot

// Test: Dot between identifiers
tokens = lex("math.add")
assert tokens[0].type == identifier
assert tokens[0].lexeme == "math"
assert tokens[1].type == dot
assert tokens[2].type == identifier
assert tokens[2].lexeme == "add"

// Test: Full call
tokens = lex("math.add(1, 2)")
assert tokens[0].type == identifier  // math
assert tokens[1].type == dot         // .
assert tokens[2].type == identifier  // add
assert tokens[3].type == lparen      // (
assert tokens[4].type == integer     // 1
// ... etc
```

### What This Enables

The lexer now produces correct tokens for dot notation:

```
Input:  math.add(1, 2)
Tokens: [identifier:math] [dot] [identifier:add] [lparen] [integer:1] [comma] [integer:2] [rparen]

Parser can now see the dot and handle the namespace.function pattern!
```

---

## Sub-lesson 5.3: Updating parsePrimary

### The Problem

The parser sees tokens like `[math] [.] [add] [(] ...]` but doesn't know what to do with the dot:

```
Current parsePrimary:

see identifier "math" → create identifier_ref { name: "math" }
see dot → ERROR: unexpected token '.'
```

We need to recognize the pattern: `identifier DOT identifier LPAREN`

### The Solution

When we see an identifier, look ahead for a dot. If found, this is namespace.function syntax.

**Updated parsePrimary:**

```
parsePrimary(self, allocator) -> Node {
    // Handle parenthesized expressions
    if self.see(lparen) {
        self.consume()  // eat '('
        expr = self.parseExpression(allocator)
        self.expect(rparen)
        return expr
    }

    // Handle numbers
    if self.see(integer) {
        token = self.consume()
        return Node.int_literal { value: token.value, token: token }
    }

    // Handle identifiers (and namespace.function)
    if self.see(identifier) {
        token = self.consume()  // e.g., "math"

        // NEW: Check for namespace.function() syntax
        if self.see(dot) {
            self.consume()  // eat the '.'

            // Expect function name
            fn_token = self.expect(identifier)  // e.g., "add"

            // Combine: "math" + "_" + "add" = "math_add"
            combined_name = format("{}_{}", token.lexeme, fn_token.lexeme)

            // Is it a function call?
            if self.see(lparen) {
                return self.parseFnCallWithName(allocator, combined_name, token)
            }

            // If not a call, it's a namespaced variable reference
            // (You might not support this, but here's how)
            return Node.identifier_ref { name: combined_name, token: token }
        }

        // Regular identifier - function call or variable
        if self.see(lparen) {
            return self.parseFnCall(allocator, token)
        }

        return Node.identifier_ref { name: token.lexeme, token: token }
    }

    // Error: unexpected token
    self.error("Expected expression, got {}", self.current().type)
}
```

**Flow Diagram:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ parsePrimary FLOW WITH DOT NOTATION                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Input: math.add(1, 2)                                               │
│                                                                     │
│ 1. see(identifier)? YES → consume "math"                            │
│                                                                     │
│ 2. see(dot)? YES → consume "."                                      │
│                                                                     │
│ 3. expect(identifier) → get "add"                                   │
│                                                                     │
│ 4. combined_name = "math" + "_" + "add" = "math_add"                │
│                                                                     │
│ 5. see(lparen)? YES → parseFnCallWithName("math_add")               │
│                                                                     │
│ 6. Result: FnCall { name: "math_add", args: [1, 2] }               │
│                                                                     │
│ Input: helper(x)  (no dot)                                          │
│                                                                     │
│ 1. see(identifier)? YES → consume "helper"                          │
│                                                                     │
│ 2. see(dot)? NO                                                     │
│                                                                     │
│ 3. see(lparen)? YES → parseFnCall("helper")                         │
│                                                                     │
│ 4. Result: FnCall { name: "helper", args: [x] }                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Update `parsePrimary()` to check for dot after identifier
2. Test:

```
// Test: Dot notation parses correctly
input = "math.add(1, 2)"
ast = parse(input)

assert ast.fn_call.name == "math_add"  // Combined!
assert ast.fn_call.args.len == 2

// Test: Regular call still works
input = "helper(x)"
ast = parse(input)

assert ast.fn_call.name == "helper"  // Not modified
```

### What This Enables

Both syntaxes work in the parser:

```
// Dot notation (preferred)
const a = math.add(1, 2);    // Parsed as call to "math_add"

// Direct call (also works)
const b = math_add(1, 2);    // Parsed as call to "math_add"

// Local function
const c = helper(a, b);      // Parsed as call to "helper"
```

---

## Sub-lesson 5.4: Name Combination and Edge Cases

### The Problem

The basic combination `namespace + "_" + function` works, but there are edge cases:

```
// What if the namespace or function name contains underscores?
import "my_math.mini" as my_math;  // namespace: "my_math"
my_math.add(1, 2)                   // should become: my_math_add

// What about deeply nested accesses?
math.vector.normalize(v)            // Should this work?

// What about calling without arguments?
io.newline()                        // Zero-arg call
```

### The Solution

Handle these cases explicitly in your implementation.

**Basic Combination (Already Done):**

```
// In parsePrimary, when we see dot:
combined_name = format("{}_{}", namespace_token.lexeme, fn_token.lexeme)

// Examples:
"math" + "_" + "add"           = "math_add"
"utils" + "_" + "format"       = "utils_format"
"my_math" + "_" + "add"        = "my_math_add"  // Works fine!
```

**Handling Zero-Arg Calls:**

```
// This should already work with your parseFnCallWithName:

parseFnCallWithName(self, allocator, name, token) -> Node {
    self.expect(lparen)
    args = []

    // Only parse args if not immediately ')'
    if not self.see(rparen) {
        while true {
            arg = self.parseExpression(allocator)
            args.append(arg)
            if not self.see(comma) { break }
            self.consume()  // eat comma
        }
    }

    self.expect(rparen)

    return Node.fn_call {
        name: name,
        args: args,  // Empty list for zero-arg calls
        token: token,
    }
}

// io.newline() → FnCall { name: "io_newline", args: [] }
```

**Multiple Dots (Not Supported):**

For simplicity, we only support one level: `namespace.function`

```
// NOT supported:
math.vector.normalize(v)  // Two dots

// Workaround: User must import deeper
import "math/vector.mini" as vec;
vec.normalize(v);  // Works!
```

If you want to support deeper nesting:

```
// Could extend parser to loop:
parsePrimary(self, allocator) -> Node {
    if self.see(identifier) {
        parts = [self.consume().lexeme]

        // Collect all dot-separated parts
        while self.see(dot) {
            self.consume()  // eat dot
            parts.append(self.expect(identifier).lexeme)
        }

        // Combine all: ["math", "vector", "normalize"] → "math_vector_normalize"
        combined = join(parts, "_")

        if self.see(lparen) {
            return self.parseFnCallWithName(allocator, combined, token)
        }
        // ...
    }
}
```

### Matching Caller and Callee

The key insight: both sides use the same convention:

```
┌─────────────────────────────────────────────────────────────────────┐
│ NAME MATCHING                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ CALLER SIDE (parsePrimary):                                         │
│   math.add(1, 2)                                                    │
│        ↓                                                            │
│   "math" + "_" + "add" = "math_add"                                 │
│        ↓                                                            │
│   FnCall { name: "math_add", args: [1, 2] }                        │
│                                                                     │
│ CALLEE SIDE (generateProgram):                                      │
│   import "math.mini" as math                                        │
│   math.mini defines: fn add(...)                                    │
│        ↓                                                            │
│   "math" + "_" + "add" = "math_add"                                 │
│        ↓                                                            │
│   Function { name: "math_add", body: ... }                          │
│                                                                     │
│ MATCH! Call resolves to correct function.                           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Test various call patterns:

```
// Test: Basic dot notation
input = "math.add(1, 2)"
ast = parse(input)
assert ast.fn_call.name == "math_add"

// Test: Zero-arg call
input = "io.newline()"
ast = parse(input)
assert ast.fn_call.name == "io_newline"
assert ast.fn_call.args.len == 0

// Test: Namespace with underscore
input = "my_utils.helper(x)"
ast = parse(input)
assert ast.fn_call.name == "my_utils_helper"

// Test: Regular call (no dot)
input = "local_fn(a, b, c)"
ast = parse(input)
assert ast.fn_call.name == "local_fn"  // Unchanged
```

2. End-to-end test:

```
// Create files:

// main.mini
import "math.mini" as math;
fn main() i32 {
    return math.add(10, 5);
}

// math.mini
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Compile and run:
output = compile("main.mini")
result = run(output)
assert result == 15  // 10 + 5
```

### What This Enables

Complete, clean import syntax:

```
import "graphics.mini" as gfx;
import "audio.mini" as sfx;
import "math.mini" as math;

fn main() i32 {
    gfx.init(800, 600);
    sfx.init();

    const angle = math.radians(45);
    const x = math.cos(angle);
    const y = math.sin(angle);

    gfx.draw_point(x, y);
    sfx.play("beep");

    return 0;
}
```

Everything works together:
- `gfx.init` → calls `gfx_init` (defined in graphics.mini)
- `math.cos` → calls `math_cos` (defined in math.mini)
- Names never collide even if multiple files have `init`

---

## Summary: Dot Notation

```
┌────────────────────────────────────────────────────────────────────┐
│ DOT NOTATION - Complete Implementation                             │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ New Token:                                                         │
│   dot  -  The '.' character                                        │
│                                                                    │
│ Parser Change (parsePrimary):                                      │
│   1. See identifier? Consume it                                    │
│   2. See dot? Consume it, get function name                        │
│   3. Combine: namespace + "_" + function                           │
│   4. Parse as function call with combined name                     │
│                                                                    │
│ Transformation:                                                    │
│   math.add(1, 2)  →  FnCall { name: "math_add", args: [1, 2] }    │
│                                                                    │
│ Why It Works:                                                      │
│   Caller: math.add → "math_add" (parser)                           │
│   Callee: import as math → "math_add" (generateProgram)            │
│   SAME NAME → Call resolves correctly!                             │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Section Complete!

Congratulations! You've built a complete multi-file import system:

| Module | What You Built | Key Concept |
|--------|---------------|-------------|
| 1. Compilation Units | Data structures for files | CompilationUnit, Import |
| 2. Import Parsing | `import "file" as ns;` syntax | Tokens, AST node, parser |
| 3. Loading Imports | Recursive file loading | Path resolution, cycle detection |
| 4. Namespace Prefixing | `add` → `math_add` | Collision prevention |
| 5. Dot Notation | `math.add` → `math_add` | Clean user syntax |

**The Complete Flow:**

```
Source:
  import "math.mini" as math;
  fn main() { return math.add(1, 2); }

→ Parse import → Load math.mini → Extract functions
→ Prefix: add → math_add
→ Parse call: math.add → math_add
→ Code generation: call math_add(1, 2)
→ Result: 3
```

---

## What's Next

Your compiler now handles multiple files! But recompiling everything every time is slow. Let's add caching.

**Next: [Section 2: Incremental Compilation](../../02-incremental-compilation/)** - Cache compiled results for faster builds

---

## Complete Code Reference

For a complete implementation, see:
- `src/token.zig` - Token types including `dot`
- `src/ast.zig` - `parsePrimary()` with dot notation handling
