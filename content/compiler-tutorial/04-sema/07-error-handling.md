---
title: "4.7: Error Handling"
weight: 7
---

# Lesson 4.7: Error Handling

Report meaningful error messages and recover gracefully.

---

## Goal

Provide helpful error messages and analyze as much as possible despite errors.

---

## Types of Errors

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SEMANTIC ERRORS                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. UNDEFINED VARIABLE                                                     │
│      return x;     // x was never declared                                  │
│                                                                              │
│   2. DUPLICATE DECLARATION                                                  │
│      const x = 1;                                                           │
│      const x = 2;  // x already exists                                      │
│                                                                              │
│   3. TYPE MISMATCH                                                          │
│      const x: i32 = true;  // bool assigned to i32                          │
│                                                                              │
│   4. INCOMPATIBLE TYPES                                                     │
│      return a + b;  // a is i32, b is i64                                   │
│                                                                              │
│   5. RETURN TYPE MISMATCH                                                   │
│      fn foo() i32 { return; }  // void vs i32                               │
│                                                                              │
│   6. UNKNOWN TYPE                                                           │
│      const x: unknown = 5;  // "unknown" isn't a type                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Error Message Structure

Good error messages include:

```
Error {
    message: string,        // What went wrong
    location: Location,     // Where (line, column)
    context: string,        // Optional: source code snippet
}

Location {
    line: integer,
    column: integer,
    file: string,           // Optional for multi-file
}
```

---

## Example Error Messages

```
Error: Undefined variable 'x'
  --> source.txt:5:12
    |
  5 |     return x;
    |            ^ not found in this scope

Error: Type mismatch in '+': i32 vs i64
  --> source.txt:3:14
    |
  3 |     return a + b;
    |              ^ cannot add i32 and i64

Error: Variable 'x' already declared
  --> source.txt:4:11
    |
  2 |     const x: i32 = 1;
    |           - first declared here
  4 |     const x: i32 = 2;
    |           ^ redeclared here
```

---

## Error Collector

Don't stop at the first error - collect them all:

```
ErrorCollector {
    errors: Error[]

    report(message, location):
        errors.append(Error { message, location })

    hasErrors() → boolean:
        return length(errors) > 0

    printAll():
        for error in errors:
            print(formatError(error))
}
```

---

## Error Recovery Strategy

Use ERROR type to continue analysis:

```
function analyzeInstruction(instr):
    switch instr.tag:
        DECL_REF:
            symbol = symbol_table.lookup(instr.data.name)
            if symbol == null:
                errors.report(
                    "Undefined variable '" + instr.data.name + "'",
                    instr.location
                )
                // Return error instruction but continue
                return AIRInstruction {
                    tag: ERROR_INSTR,
                    type: ERROR
                }
            // ... normal case

        ADD:
            lhs_type = type_of[instr.data.lhs]
            rhs_type = type_of[instr.data.rhs]

            // Don't report error if operands already have errors
            if lhs_type == ERROR or rhs_type == ERROR:
                return AIRInstruction { type: ERROR }

            if lhs_type != rhs_type:
                errors.report(
                    "Type mismatch in '+': " + typeName(lhs_type) +
                    " vs " + typeName(rhs_type),
                    instr.location
                )
                return AIRInstruction { type: ERROR }

            // ... normal case
```

---

## Avoiding Cascading Errors

Wrong approach:
```
const x: i32 = undefined_var;   // Error: undefined
return x + 1;                    // Error: x has error type
return x * 2;                    // Error: x has error type
// 3 errors reported for 1 mistake!
```

Right approach:
```
const x: i32 = undefined_var;   // Error: undefined, x gets ERROR type
return x + 1;                    // x is ERROR, skip check (no new error)
return x * 2;                    // x is ERROR, skip check (no new error)
// 1 error reported!
```

---

## Tracking Locations

Pass location through the pipeline:

```
// In lexer: tokens have locations
Token {
    type: TokenType,
    lexeme: string,
    line: integer,
    column: integer
}

// In AST: nodes have locations
BinaryExpr {
    left: Expr,
    operator: Token,  // Contains location
    right: Expr
}

// In ZIR: instructions track source location
Instruction {
    tag: InstrTag,
    data: ...,
    location: Location   // Preserved from AST
}
```

---

## Error Categories

Organize errors by severity:

```
enum Severity {
    ERROR,      // Prevents compilation
    WARNING,    // Suspicious but allowed
    NOTE,       // Additional context
}

Error {
    severity: Severity,
    message: string,
    location: Location
}
```

Example with notes:
```
Error: Variable 'x' already declared
  --> source.txt:4:11

Note: Previous declaration was here
  --> source.txt:2:11
```

---

## Verify Your Implementation

### Test 1: Undefined variable
```
Source:
fn foo() i32 {
    return x;
}

Errors:
    "Undefined variable 'x'" at line 2
```

### Test 2: Duplicate declaration
```
Source:
fn foo() i32 {
    const x: i32 = 1;
    const x: i32 = 2;
    return x;
}

Errors:
    "Variable 'x' already declared" at line 3
```

### Test 3: Type mismatch
```
Source:
fn foo(a: i32, b: i64) i32 {
    return a + b;
}

Errors:
    "Type mismatch in '+': i32 vs i64" at line 2
```

### Test 4: Multiple errors
```
Source:
fn foo() i32 {
    return x + y;
}

Errors:
    "Undefined variable 'x'" at line 2
    "Undefined variable 'y'" at line 2
    (NOT: "Cannot add ERROR and ERROR")
```

### Test 5: Return type mismatch
```
Source:
fn foo() i32 {
    return;
}

Errors:
    "Return type mismatch: expected i32, got void" at line 2
```

---

## What's Next

Let's put together the complete semantic analyzer.

Next: [Lesson 4.8: Complete Sema](../08-putting-together/) →
