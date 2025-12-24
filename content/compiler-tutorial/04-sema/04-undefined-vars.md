---
title: "4.4: Undefined Variables"
weight: 4
---

# Lesson 4.4: Undefined Variables

Detect when a variable is used but never declared.

---

## The Error

```
fn foo() i32 {
    return x;       // x was never declared!
}
```

Expected output:
```
1:19: error: undefined variable "x"
fn foo() i32 { return x; }
                      ^
```

---

## When to Check

Check when processing `decl_ref` instructions:

```
ZIR: %2 = decl_ref("x")

Question: Is "x" in our names table?
  - Yes → return its type
  - No  → error: undefined variable
```

---

## The Check

```
decl_ref(name):
    type = names.get(name)

    if type == null:
        error: undefined variable "name"
        return null

    return type
```

---

## Error Data Structure

```
Error = union {
    undefined_variable: struct {
        name: []const u8,              // Which variable
        inst: *const Instruction,       // Points to decl_ref
    },
}
```

Following the pointer chain:
```
error.inst                              // → decl_ref instruction
     .node                              // → identifier_ref AST node
     .token                             // → Token
     .line, .col                        // → 1, 19
```

---

## Collecting Errors

Don't stop at first error - collect them all:

```
function analyzeFunction(func):
    errors = []
    names = {}
    inst_types = []

    // ... register parameters ...

    for i in 0..instruction_count:
        inst = instruction_at(i)

        result_type = switch inst:
            decl_ref(d):
                type = names.get(d.name)
                if type == null:
                    errors.append({
                        undefined_variable: {
                            name: d.name,
                            inst: inst
                        }
                    })
                    null        // Use null as placeholder
                else:
                    type

            // ... other cases ...

        inst_types.append(result_type)

    return errors
```

---

## Multiple Errors

One source file can have multiple undefined variables:

```
fn foo() i32 {
    return x + y;
}
```

Both `x` and `y` are undefined. Report both:

```
1:22: error: undefined variable "x"
fn foo() i32 { return x + y; }
                      ^
1:26: error: undefined variable "y"
fn foo() i32 { return x + y; }
                          ^
```

---

## Formatting the Error

```
function errorToString(error, source):
    token = getToken(error)
    message = getMessage(error)
    line_content = getLine(source, token.line)
    caret = makeCaretLine(token.col)

    return "{line}:{col}: error: {message}\n{line_content}\n{caret}\n"

function getToken(error):
    switch error:
        undefined_variable:
            return error.inst.decl_ref.node.identifier_ref.token

function getMessage(error):
    switch error:
        undefined_variable:
            return "undefined variable \"{name}\""
```

---

## Helper: Get Source Line

Extract a specific line from the source:

```
function getLine(source, line_num):
    lines = source.split('\n')
    for i in 1..(line_num - 1):
        skip lines.next()
    return lines.next() or ""
```

---

## Helper: Make Caret Line

Create spaces followed by `^`:

```
function makeCaretLine(col):
    // col is 1-based
    spaces = " " * (col - 1)
    return spaces + "^"
```

Example:
```
col = 19
makeCaretLine(19) → "                  ^"
                     └── 18 spaces ───┘
```

---

## Complete Example

```
Source:
fn foo() i32 { return x; }

Tokens:
    ... Token{ lexeme: "x", line: 1, col: 22 } ...

AST:
    identifier_ref{ name: "x", token: → Token }

ZIR:
    %0 = decl_ref("x")   ← node: → AST node

Sema:
    names = {}           ← no "x" registered!

    Processing %0:
        decl_ref("x")
        names.get("x") → null
        Error! undefined_variable

Error formatting:
    token.line = 1
    token.col = 22
    getLine(source, 1) = "fn foo() i32 { return x; }"
    makeCaretLine(22) = "                     ^"

Output:
    1:22: error: undefined variable "x"
    fn foo() i32 { return x; }
                         ^
```

---

## Valid Cases: No Error

These should NOT produce errors:

```
// Parameter usage - "n" is registered from params
fn square(n: i32) i32 {
    return n * n;           // n exists!
}

// Local variable usage - "x" declared before use
fn calc() i32 {
    const x = 10;
    return x;               // x exists!
}
```

---

## Verify Your Implementation

### Test 1: Undefined variable
```
Source: fn foo() i32 { return x; }
Error: "undefined variable \"x\"" at line 1
```

### Test 2: Multiple undefined
```
Source: fn foo() i32 { return x + y; }
Errors:
  - "undefined variable \"x\""
  - "undefined variable \"y\""
```

### Test 3: Parameter is valid
```
Source: fn square(x: i32) i32 { return x * x; }
Errors: (none)
```

### Test 4: Local variable is valid
```
Source: fn foo() i32 { const x = 10; return x; }
Errors: (none)
```

---

## Common Mistake: Order Matters

Variables must be declared before use:

```
fn foo() i32 {
    return x;           // Error: x not yet declared
    const x = 10;
}
```

ZIR processes top-to-bottom:
```
%0 = decl_ref("x")      // Lookup fails - x not in names yet
%1 = constant(10)
%2 = decl("x", %1)      // x registered here, too late!
```

This is correct behavior - use before declaration is an error.

---

## What's Next

Now let's detect when the same variable is declared twice.

Next: [Lesson 4.5: Duplicate Declarations](../05-duplicate-decls/) →
