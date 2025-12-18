---
title: "6.3: Test Suite"
weight: 3
---

# Lesson 6.3: Comprehensive Testing

Build a test suite for your compiler.

---

## Goal

Create tests that verify each compiler stage and the full pipeline.

---

## Test Categories

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        TEST CATEGORIES                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. UNIT TESTS       Test individual components                            │
│   2. STAGE TESTS      Test each compiler stage                              │
│   3. INTEGRATION      Test the full pipeline                                │
│   4. ERROR TESTS      Verify error messages                                 │
│   5. EXECUTION TESTS  Run compiled programs                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Unit Tests: Lexer

```
// Test: Single tokens
assert tokenize("+")[0].type == PLUS
assert tokenize("42")[0].type == NUMBER
assert tokenize("fn")[0].type == KEYWORD_FN
assert tokenize("foo")[0].type == IDENTIFIER

// Test: Multiple tokens
tokens = tokenize("1 + 2")
assert tokens[0].type == NUMBER
assert tokens[1].type == PLUS
assert tokens[2].type == NUMBER

// Test: Keywords vs identifiers
assert tokenize("fn")[0].type == KEYWORD_FN
assert tokenize("function")[0].type == IDENTIFIER

// Test: Line tracking
tokens = tokenize("a\nb\nc")
assert tokens[0].line == 1
assert tokens[1].line == 2
assert tokens[2].line == 3
```

---

## Unit Tests: Parser

```
// Test: Number literal
ast = parse(tokenize("42"))
assert ast.type == NumberExpr
assert ast.value == 42

// Test: Binary expression
ast = parse(tokenize("1 + 2"))
assert ast.type == BinaryExpr
assert ast.operator == PLUS

// Test: Precedence
ast = parse(tokenize("1 + 2 * 3"))
// Should be: 1 + (2 * 3), not (1 + 2) * 3
assert ast.type == BinaryExpr
assert ast.operator == PLUS
assert ast.right.type == BinaryExpr
assert ast.right.operator == STAR

// Test: Function
ast = parse(tokenize("fn foo() i32 { return 0; }"))
assert ast.declarations[0].name == "foo"
assert ast.declarations[0].return_type.name == "i32"
```

---

## Unit Tests: ZIR

```
// Test: Constant flattening
zir = generateZIR(parse(tokenize("fn f() i32 { return 42; }")))
fn = zir.functions[0]
assert fn.instructions[0].tag == CONSTANT
assert fn.instructions[0].data.value == 42

// Test: Binary operation
zir = generateZIR(parse(tokenize("fn f() i32 { return 1 + 2; }")))
fn = zir.functions[0]
assert fn.instructions[0].tag == CONSTANT  // 1
assert fn.instructions[1].tag == CONSTANT  // 2
assert fn.instructions[2].tag == ADD       // +

// Test: Parameters
zir = generateZIR(parse(tokenize("fn f(x: i32) i32 { return x; }")))
fn = zir.functions[0]
assert fn.instructions[0].tag == PARAM_REF
assert fn.instructions[0].data.param_index == 0
```

---

## Unit Tests: Sema

```
// Test: Type inference
air = analyze(generateZIR(parse(tokenize("fn f() i32 { return 42; }"))))
fn = air.functions[0]
assert fn.instructions[0].type == I32

// Test: Undefined variable error
result = analyze(generateZIR(parse(tokenize("fn f() i32 { return x; }"))))
assert result.errors.hasErrors()
assert "undefined" in result.errors[0].message.lower()

// Test: Type mismatch error
// Would need i64 support to test properly
```

---

## Integration Tests

```
// Test: Minimal program compiles
result = compile("fn main() i32 { return 0; }")
assert result.success
assert "#include" in result.output
assert "int32_t main()" in result.output

// Test: Arithmetic
result = compile("fn main() i32 { return 1 + 2 * 3; }")
assert result.success

// Test: Local variables
result = compile("""
fn main() i32 {
    const x: i32 = 5;
    return x;
}
""")
assert result.success

// Test: Multiple functions
result = compile("""
fn helper() i32 { return 1; }
fn main() i32 { return 0; }
""")
assert result.success
```

---

## Error Tests

```
// Test: Syntax error
result = compile("fn main() { }")  // Missing return type
assert not result.success
assert "expected" in result.errors[0].message.lower()

// Test: Undefined variable
result = compile("fn main() i32 { return undefined; }")
assert not result.success
assert "undefined" in result.errors[0].message.lower()

// Test: Duplicate declaration
result = compile("""
fn main() i32 {
    const x: i32 = 1;
    const x: i32 = 2;
    return x;
}
""")
assert not result.success
assert "already" in result.errors[0].message.lower()
```

---

## Execution Tests

```
function testExecution(source, expected_exit_code):
    result = compile(source)
    assert result.success

    writeFile("/tmp/test.c", result.output)
    system("cc /tmp/test.c -o /tmp/test")
    exit_code = system("/tmp/test")

    assert exit_code == expected_exit_code

// Test cases
testExecution("fn main() i32 { return 0; }", 0)
testExecution("fn main() i32 { return 42; }", 42)
testExecution("fn main() i32 { return 1 + 2; }", 3)
testExecution("fn main() i32 { return 2 * 3; }", 6)
testExecution("fn main() i32 { return 10 - 4; }", 6)
testExecution("fn main() i32 { return 15 / 3; }", 5)
testExecution("fn main() i32 { return 1 + 2 * 3; }", 7)
testExecution("fn main() i32 { return (1 + 2) * 3; }", 9)
testExecution("fn main() i32 { return -5; }", 251)  // 256 - 5 due to unsigned exit code
testExecution("""
fn main() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    return x + y;
}
""", 8)
```

---

## Test Organization

```
tests/
├── lexer/
│   ├── test_tokens.py
│   ├── test_whitespace.py
│   └── test_keywords.py
├── parser/
│   ├── test_expressions.py
│   ├── test_statements.py
│   └── test_functions.py
├── zir/
│   └── test_generation.py
├── sema/
│   ├── test_types.py
│   └── test_errors.py
├── codegen/
│   └── test_output.py
├── integration/
│   └── test_full_pipeline.py
└── execution/
    └── test_programs.py
```

---

## Test Runner

```
function runAllTests():
    passed = 0
    failed = 0

    for test in getAllTests():
        try:
            test.run()
            passed++
            print("✓ " + test.name)
        catch error:
            failed++
            print("✗ " + test.name + ": " + error)

    print("\nResults: " + passed + " passed, " + failed + " failed")
```

---

## What's Next

Let's explore how to extend your compiler.

Next: [Lesson 6.4: Extensions](../04-extensions/) →
