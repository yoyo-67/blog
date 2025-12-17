---
title: "3.5: Parameter References"
weight: 5
---

# Lesson 3.5: Function Parameter References

Handle references to function parameters like `a` and `b` in `fn add(a: i32, b: i32)`.

---

## Goal

Generate `param_ref` instructions when referencing function parameters.

---

## Parameters vs Local Variables

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARAMETERS VS LOCALS                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   fn add(a: i32, b: i32) i32 {                                              │
│       const sum: i32 = a + b;                                               │
│       return sum;                                                           │
│   }                                                                         │
│                                                                              │
│   Parameters: a, b                                                          │
│     - Come from function signature                                          │
│     - Referenced by INDEX (param_ref(0), param_ref(1))                     │
│     - Available at function start                                           │
│                                                                              │
│   Locals: sum                                                               │
│     - Declared inside function body                                         │
│     - Referenced by NAME (decl_ref("sum"))                                 │
│     - Created during execution                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Index vs Name?

Parameters are special:
- They're always available (no declaration needed)
- Their order is significant (matches calling convention)
- Using index simplifies code generation later

```
fn add(a: i32, b: i32) i32 { return a + b; }

With names:
    %0 = decl_ref("a")    // Which "a"? Need to track scope.
    %1 = decl_ref("b")
    %2 = add(%0, %1)
    %3 = ret(%2)

With indices:
    %0 = param_ref(0)     // First parameter, always
    %1 = param_ref(1)     // Second parameter, always
    %2 = add(%0, %1)
    %3 = ret(%2)
```

---

## Track Parameters

When generating a function, know which names are parameters:

```
ZIRGenerator {
    instructions: Instruction[]
    param_names: Map<string, integer>   // name → param index
}

function generateFunction(fn_decl):
    // Build parameter map
    param_names = {}
    for i, param in enumerate(fn_decl.params):
        param_names[param.name] = i

    // Generate body with this context
    generator = ZIRGenerator {
        instructions: [],
        param_names: param_names
    }
    generator.generateBlock(fn_decl.body)

    return FunctionZIR {
        name: fn_decl.name,
        params: fn_decl.params,
        return_type: fn_decl.return_type,
        instructions: generator.instructions
    }
```

---

## Updated generateExpr

```
function generateExpr(expr) → InstrRef:
    switch expr.type:
        // ... other cases ...

        IdentifierExpr:
            name = expr.name

            // Is it a parameter?
            if name in param_names:
                index = param_names[name]
                return emit(ParamRef { index: index })

            // Otherwise, it's a local variable
            return emit(DeclRef { name: name })
```

---

## Full Example

```
Source:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

Step 1: Build param_names
    param_names = { "a": 0, "b": 1 }

Step 2: Generate body
    return a + b;

    generateReturn():
        value = generateExpr(BinaryExpr(Identifier("a"), +, Identifier("b"))):
            lhs = generateExpr(IdentifierExpr("a")):
                "a" is in param_names at index 0
                emit(ParamRef { index: 0 }) → 0
            rhs = generateExpr(IdentifierExpr("b")):
                "b" is in param_names at index 1
                emit(ParamRef { index: 1 }) → 1
            emit(Add { lhs: 0, rhs: 1 }) → 2
        emit(Ret { value: 2 }) → 3

Final ZIR:
    function "add":
      params: [("a", i32), ("b", i32)]
      return_type: i32
      body:
        %0 = param_ref(0)
        %1 = param_ref(1)
        %2 = add(%0, %1)
        %3 = ret(%2)
```

---

## Parameters and Locals Together

```
Source:
fn calculate(x: i32) i32 {
    const doubled: i32 = x * 2;
    return doubled + x;
}

param_names = { "x": 0 }

ZIR:
    %0 = param_ref(0)         // x
    %1 = constant(2)
    %2 = mul(%0, %1)          // x * 2
    %3 = decl("doubled", %2)
    %4 = decl_ref("doubled")
    %5 = param_ref(0)         // x again
    %6 = add(%4, %5)          // doubled + x
    %7 = ret(%6)
```

Note: `x` generates `param_ref(0)` both times. `doubled` uses `decl` and `decl_ref`.

---

## Verify Your Implementation

### Test 1: Single parameter
```
Input:  fn square(x: i32) i32 { return x * x; }
ZIR:
    %0 = param_ref(0)
    %1 = param_ref(0)
    %2 = mul(%0, %1)
    %3 = ret(%2)
```

### Test 2: Two parameters
```
Input:  fn add(a: i32, b: i32) i32 { return a + b; }
ZIR:
    %0 = param_ref(0)
    %1 = param_ref(1)
    %2 = add(%0, %1)
    %3 = ret(%2)
```

### Test 3: Parameter order matters
```
Input:  fn sub(a: i32, b: i32) i32 { return b - a; }
ZIR:
    %0 = param_ref(1)     // b is second (index 1)
    %1 = param_ref(0)     // a is first (index 0)
    %2 = sub(%0, %1)      // b - a
    %3 = ret(%2)
```

### Test 4: Mix with locals
```
Input:
fn calc(n: i32) i32 {
    const result: i32 = n + 1;
    return result;
}
ZIR:
    %0 = param_ref(0)
    %1 = constant(1)
    %2 = add(%0, %1)
    %3 = decl("result", %2)
    %4 = decl_ref("result")
    %5 = ret(%4)
```

### Test 5: Parameter shadowed by local
```
Input:
fn shadow(x: i32) i32 {
    const x: i32 = 99;
    return x;
}

ZIR (depends on your scoping rules):
    // If locals shadow params:
    %0 = constant(99)
    %1 = decl("x", %0)
    %2 = decl_ref("x")
    %3 = ret(%2)
```

---

## Implementation Note

Shadowing (local hiding parameter) is a design choice:

```
// Option A: Error on shadow (simple)
if name in param_names:
    error("Cannot redeclare parameter '" + name + "'")

// Option B: Allow shadow (more complex)
// Need a scope stack to track which "x" is meant
```

For our mini compiler, Option A (error) is simpler.

---

## What's Next

Let's put it together for complete function ZIR.

Next: [Lesson 3.6: Function IR](../06-function-ir/) →
