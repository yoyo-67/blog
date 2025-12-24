---
title: "4.6: Return Type Declaration"
weight: 6
---

# Lesson 4.6: Return Type Declaration

Add return types to function signatures.

---

## The Syntax

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn greet() {
    // No return type means void
}
```

Return type comes after the parameter list, before the brace.

---

## Why Return Types?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      WHY DECLARE RETURN TYPES?                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. Type Checking                                                           │
│      fn foo() i32 { return true; }   // Error: bool vs i32                   │
│                                                                              │
│   2. Documentation                                                           │
│      fn calculate(x: i32) i32        // Reader knows what to expect         │
│                                                                              │
│   3. Forward References (future)                                             │
│      fn main() { foo(); }            // Can check call before seeing body   │
│      fn foo() i32 { ... }                                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Lexer Changes

Need a token for type keywords:

```
Token.Type = enum {
    // ... existing tokens ...
    kw_i32,         // "i32"
    kw_i64,         // "i64"
    kw_bool,        // "bool"
    // Note: void can be absence of type
}
```

---

## Parser Changes

Update the function grammar:

```
Before:
    fn: 'fn' IDENTIFIER '(' parameters? ')' '{' block '}'

After:
    fn: 'fn' IDENTIFIER '(' parameters? ')' type? '{' block '}'
    type: 'i32' | 'i64' | 'bool' | IDENTIFIER
```

---

## Parsing Return Type

```
function parseFn():
    expect(kw_fn)
    name = expect(identifier).lexeme
    expect(lparen)
    params = parseParams()
    expect(rparen)

    // NEW: Optional return type
    return_type = null
    if not see(lbrace):
        return_type = parseType()

    expect(lbrace)
    block = parseBlock()
    expect(rbrace)

    return FnDecl {
        name: name,
        params: params,
        return_type: return_type,      // NEW FIELD
        block: block
    }

function parseType():
    if see(kw_i32):
        return consume().lexeme    // "i32"
    if see(kw_i64):
        return consume().lexeme    // "i64"
    if see(kw_bool):
        return consume().lexeme    // "bool"
    if see(identifier):
        return consume().lexeme    // Custom type
    error("Expected type")
```

---

## AST Node Update

```
Node = union {
    fn_decl: struct {
        name: []const u8,
        params: []Param,
        return_type: ?[]const u8,    // ← NEW: optional
        block: Block,
    },
    // ... other nodes ...
}
```

---

## ZIR Function Update

```
Function = struct {
    name: []const u8,
    params: []Param,
    return_type: ?[]const u8,    // ← NEW: optional
    zir: Zir,
}
```

---

## Void vs No Return Type

Two ways to handle missing return type:

**Option 1: Explicit void**
```
fn foo() void { }       // Must write "void"
fn bar() { }            // Syntax error
```

**Option 2: Implicit void (our choice)**
```
fn foo() { }            // Means void
fn bar() void { }       // Also means void
```

In both cases, stored as:
```
return_type: null       // or "void"
```

---

## Example Parse

```
Source: fn add(a: i32, b: i32) i32 { return a + b; }

Tokens:
    kw_fn, identifier("add"), lparen,
    identifier("a"), colon, kw_i32, comma,
    identifier("b"), colon, kw_i32, rparen,
    kw_i32,                                    // ← Return type
    lbrace, kw_return, ...

Parse result:
    FnDecl {
        name: "add",
        params: [
            Param{ name: "a", type: "i32" },
            Param{ name: "b", type: "i32" },
        ],
        return_type: "i32",                   // ← Captured!
        block: ...
    }
```

---

## Example: No Return Type

```
Source: fn greet() { }

Parse result:
    FnDecl {
        name: "greet",
        params: [],
        return_type: null,                    // ← No type specified
        block: ...
    }
```

---

## Return Type in ZIR Generation

When generating ZIR for a function, preserve the return type:

```
function generateFunction(fn_decl):
    func = Function {
        name: fn_decl.name,
        params: fn_decl.params,
        return_type: fn_decl.return_type,    // ← Copy it
        zir: Zir.init(),
    }

    // Generate body...
    for stmt in fn_decl.block:
        func.zir.generate(stmt)

    return func
```

---

## Sema Can Now Access Return Type

```
function analyzeFunction(func):
    declared_return = func.return_type    // "i32" or null

    // ... analyze instructions ...

    // Now we can check return statements!
```

---

## Return Type Inference (Optional)

If no return type is declared, infer from the return statement:

```
fn add(a: i32, b: i32) {     // No return type declared
    return a + b;             // But returns i32
}

// Inferred: return_type = "i32"
```

We'll implement this in the next lesson.

---

## Verify Your Implementation

### Test 1: Parse with return type
```
Source: fn foo() i32 { return 0; }
Result: FnDecl { return_type: "i32" }
```

### Test 2: Parse without return type
```
Source: fn foo() { }
Result: FnDecl { return_type: null }
```

### Test 3: Parse i64 return type
```
Source: fn bar() i64 { return 0; }
Result: FnDecl { return_type: "i64" }
```

### Test 4: ZIR preserves return type
```
Source: fn add(a: i32, b: i32) i32 { return a + b; }
ZIR:
    function "add":
        params: [("a", i32), ("b", i32)]
        return_type: i32                     // ← Preserved
        %0 = ...
```

---

## Common Patterns

```
// Return same type as parameter
fn square(n: i32) i32 {
    return n * n;
}

// Multiple parameters, return one type
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// No parameters, return a value
fn getAnswer() i32 {
    return 42;
}

// No return value (void)
fn doSomething() {
    // ...
}
```

---

## What's Next

Now let's check that return statements match the declared type.

Next: [Lesson 4.7: Return Type Checking](../07-return-type-check/) →
