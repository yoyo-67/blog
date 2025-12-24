---
title: "4.8: Putting It Together"
weight: 8
---

# Lesson 4.8: Putting It Together

Complete semantic analyzer implementation.

---

## What We've Built

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SEMA CHECKS                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ✓ Undefined Variables    - decl_ref to unknown name                       │
│   ✓ Duplicate Declarations - decl with existing name                        │
│   ✓ Return Type Mismatch   - return expr doesn't match signature            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Error Type

```
Error = union {
    undefined_variable: struct {
        name: []const u8,
        inst: *const Instruction,
    },

    duplicate_declaration: struct {
        name: []const u8,
        inst: *const Instruction,
    },

    return_type_mismatch: struct {
        expected: []const u8,
        actual: []const u8,
        inst: *const Instruction,
    },
}
```

---

## Error Formatting

```
function toString(error, source) → string:
    token = getToken(error)
    message = getMessage(error)
    line_content = getLine(source, token.line)
    caret = makeCaretLine(token.col)

    return "{line}:{col}: error: {message}\n{line_content}\n{caret}\n"


function getToken(error) → Token:
    switch error:
        undefined_variable:
            return error.inst.decl_ref.node.identifier_ref.token

        duplicate_declaration:
            return error.inst.decl.node.identifier.token

        return_type_mismatch:
            return error.inst.return_stmt.node.return_stmt.token


function getMessage(error) → string:
    switch error:
        undefined_variable:
            return "undefined variable \"{name}\""

        duplicate_declaration:
            return "duplicate declaration \"{name}\""

        return_type_mismatch:
            return "return type mismatch: expected {expected}, got {actual}"
```

---

## Helper Functions

```
function getLine(source, line_num) → string:
    lines = source.split('\n')
    for i in 1..(line_num - 1):
        skip lines.next()
    return lines.next() or ""


function makeCaretLine(col) → string:
    spaces = " " * (col - 1)
    return spaces + "^"
```

---

## The Main Analysis Loop

```
function analyzeProgram(program) → []Error:
    all_errors = []

    for func in program.functions():
        errors = analyzeFunction(func)
        all_errors.append(errors)

    return all_errors
```

---

## Complete analyzeFunction

```
function analyzeFunction(func) → []Error:
    errors = []

    // Track: name → type
    names = HashMap<string, string>

    // Track: instruction index → result type
    inst_types = []

    // Register parameters
    for param in func.params:
        names.put(param.name, param.type)

    // Analyze each instruction
    for i in 0..func.instructionCount():
        inst = func.instructionAt(i)

        result_type = switch inst:

            .constant:
                "i32"

            .param_ref(idx):
                func.params[idx].type

            .decl(d):
                if names.contains(d.name):
                    errors.append({
                        duplicate_declaration: {
                            name: d.name,
                            inst: inst
                        }
                    })
                else:
                    // Infer type from value
                    value_type = inst_types[d.value] or "i32"
                    names.put(d.name, value_type)
                null

            .decl_ref(d):
                names.get(d.name) or {
                    errors.append({
                        undefined_variable: {
                            name: d.name,
                            inst: inst
                        }
                    })
                    null
                }

            .add, .sub, .mul, .div:
                null    // Skip type checking for binary ops

            .return_stmt(r):
                actual_type = inst_types[r.value] or "i32"
                expected_type = func.return_type or "void"

                if actual_type != expected_type:
                    errors.append({
                        return_type_mismatch: {
                            expected: expected_type,
                            actual: actual_type,
                            inst: inst
                        }
                    })
                null

        inst_types.append(result_type)

    return errors
```

---

## Converting Errors to String

```
function errorsToString(errors, source) → string:
    result = ""

    for error in errors:
        result = result + error.toString(source)

    return result
```

---

## Complete Example

```
Source:
fn foo() i32 {
    const x = 10;
    const x = 20;
    return y;
}

ZIR:
    function "foo":
        return_type: i32
        %0 = constant(10)
        %1 = decl("x", %0)
        %2 = constant(20)
        %3 = decl("x", %2)      ← duplicate!
        %4 = decl_ref("y")       ← undefined!
        %5 = ret(%4)
```

Analysis:
```
Step 1: names = {}

Step 2: %0 = constant(10) → i32
        inst_types = [i32]

Step 3: %1 = decl("x", %0)
        names.contains("x") → false
        names.put("x", i32)
        names = {"x": i32}
        inst_types = [i32, null]

Step 4: %2 = constant(20) → i32
        inst_types = [i32, null, i32]

Step 5: %3 = decl("x", %2)
        names.contains("x") → true
        ERROR: duplicate declaration "x"
        inst_types = [i32, null, i32, null]

Step 6: %4 = decl_ref("y")
        names.get("y") → null
        ERROR: undefined variable "y"
        inst_types = [i32, null, i32, null, null]

Step 7: %5 = ret(%4)
        actual_type = inst_types[4] = null → "i32" (default)
        expected_type = "i32"
        No error (types match)
        inst_types = [i32, null, i32, null, null, null]
```

Output:
```
1:22: error: duplicate declaration "x"
fn foo() i32 { const x = 10; const x = 20; return y; }
                                   ^
1:42: error: undefined variable "y"
fn foo() i32 { const x = 10; const x = 20; return y; }
                                                  ^
```

---

## Test Suite

### Test 1: Undefined variable
```
Source: fn foo() i32 { return x; }
Expected:
    1:23: error: undefined variable "x"
    fn foo() i32 { return x; }
                          ^
```

### Test 2: Duplicate declaration
```
Source: fn foo() i32 { const x = 1; const x = 2; return x; }
Expected:
    1:35: error: duplicate declaration "x"
    fn foo() i32 { const x = 1; const x = 2; return x; }
                                      ^
```

### Test 3: Valid code - no errors
```
Source: fn foo() i32 { const x = 10; return x; }
Expected: (no errors)
```

### Test 4: Parameter usage is valid
```
Source: fn square(x: i32) i32 { return x * x; }
Expected: (no errors)
```

### Test 5: Multiple errors
```
Source: fn foo() i32 { return a + b; }
Expected:
    1:23: error: undefined variable "a"
    1:27: error: undefined variable "b"
```

### Test 6: Return type mismatch
```
Source: fn foo(a: i32, b: i64) i32 { return b; }
Expected:
    error: return type mismatch: expected i32, got i64
```

---

## The Pointer Chain in Action

```
Source: fn foo() i32 { return x; }

Error.undefined_variable
  │
  └── inst: *const Instruction
        │
        └── Instruction.decl_ref
              │
              └── node: *const Node
                    │
                    └── Node.identifier_ref
                          │
                          └── token: *const Token
                                │
                                └── Token { line: 1, col: 23 }

Following the chain:
  error.inst.decl_ref.node.identifier_ref.token
    → Token { line: 1, col: 23 }
```

---

## Architecture Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SEMA ARCHITECTURE                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input: ZIR Program                                                         │
│     └── Function[]                                                           │
│           └── name, params, return_type, instructions                        │
│                                                                              │
│   State per function:                                                        │
│     └── names: HashMap<string, type>                                         │
│     └── inst_types: []?type                                                  │
│     └── errors: []Error                                                      │
│                                                                              │
│   Output: []Error                                                            │
│     └── Each error points to its instruction                                 │
│     └── Instruction points to AST node                                       │
│     └── AST node points to token                                             │
│     └── Token has line/col                                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What You've Learned

1. **Error structure** - Union type with different error kinds
2. **Pointer chains** - Errors point back to source through instruction → node → token
3. **Name tracking** - HashMap for declared names
4. **Type tracking** - Array for instruction result types
5. **Error recovery** - Continue analysis after errors
6. **Error formatting** - Line numbers, source snippets, carets

---

## Future Extensions

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           FUTURE WORK                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Type checking binary ops                                                   │
│     i32 + i64 → error                                                        │
│                                                                              │
│   Nested scopes                                                              │
│     { const x = 1; { const x = 2; } }  // shadowing                         │
│                                                                              │
│   Function calls                                                             │
│     fn foo(a: i32) i32 { return bar(a); }                                   │
│     Check: does bar exist? are arg types correct?                            │
│                                                                              │
│   Missing return                                                             │
│     fn foo() i32 { const x = 1; }  // Error: no return                       │
│                                                                              │
│   Dead code                                                                  │
│     fn foo() i32 { return 1; const x = 2; }  // Warning: dead code          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

Congratulations! You've built a complete semantic analyzer that:
- Detects undefined variables
- Detects duplicate declarations
- Checks return types

In the next section, we'll generate machine code from our analyzed program.

Next: [Section 5: Code Generation](../../05-codegen/) →
