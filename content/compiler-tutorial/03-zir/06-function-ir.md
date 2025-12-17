---
title: "3.6: Function IR"
weight: 6
---

# Lesson 3.6: Complete Function ZIR

Generate ZIR for entire functions.

---

## Goal

Transform FnDecl AST nodes into complete FunctionZIR structures.

---

## Function ZIR Structure

```
FunctionZIR {
    name: string,
    params: Parameter[],
    return_type: TypeExpr,
    instructions: Instruction[]
}
```

---

## Generate Function

```
function generateFunction(fn_decl) → FunctionZIR:
    // Create generator with parameter context
    generator = ZIRGenerator {
        instructions: [],
        param_names: buildParamMap(fn_decl.params)
    }

    // Generate all statements in the body
    for stmt in fn_decl.body.statements:
        generator.generateStatement(stmt)

    return FunctionZIR {
        name: fn_decl.name,
        params: fn_decl.params,
        return_type: fn_decl.return_type,
        instructions: generator.instructions
    }

function buildParamMap(params) → Map<string, integer>:
    map = {}
    for i, param in enumerate(params):
        map[param.name] = i
    return map
```

---

## Complete generateStatement

```
function generateStatement(stmt):
    switch stmt.type:
        VarDecl:
            value = generateExpr(stmt.value)
            emit(Decl { name: stmt.name, value: value })

        ReturnStmt:
            if stmt.value != null:
                value = generateExpr(stmt.value)
                emit(Ret { value: value })
            else:
                emit(RetVoid {})

        Block:
            for s in stmt.statements:
                generateStatement(s)
```

---

## Full Example

```
Source:
fn add(a: i32, b: i32) i32 {
    const result: i32 = a + b;
    return result;
}

AST:
    FnDecl {
        name: "add",
        params: [Parameter("a", i32), Parameter("b", i32)],
        return_type: i32,
        body: Block {
            statements: [
                VarDecl {
                    name: "result",
                    type: i32,
                    value: BinaryExpr(Identifier("a"), +, Identifier("b"))
                },
                ReturnStmt {
                    value: IdentifierExpr("result")
                }
            ]
        }
    }

Generation:

1. Build param_names: { "a": 0, "b": 1 }

2. Generate statements:

   Statement 1: const result: i32 = a + b;
       value = generateExpr(BinaryExpr):
           lhs = generateExpr("a"):
               "a" in param_names → emit(ParamRef { index: 0 }) → 0
           rhs = generateExpr("b"):
               "b" in param_names → emit(ParamRef { index: 1 }) → 1
           emit(Add { lhs: 0, rhs: 1 }) → 2
       emit(Decl { name: "result", value: 2 }) → 3

   Statement 2: return result;
       value = generateExpr("result"):
           "result" not in param_names → emit(DeclRef { name: "result" }) → 4
       emit(Ret { value: 4 }) → 5

Final FunctionZIR:
    function "add":
      params: [("a", i32), ("b", i32)]
      return_type: i32
      body:
        %0 = param_ref(0)
        %1 = param_ref(1)
        %2 = add(%0, %1)
        %3 = decl("result", %2)
        %4 = decl_ref("result")
        %5 = ret(%4)
```

---

## Multiple Functions

```
function generateProgram(root) → ProgramZIR:
    functions = []
    for decl in root.declarations:
        if decl.type == FnDecl:
            fn_zir = generateFunction(decl)
            functions.append(fn_zir)
    return ProgramZIR { functions: functions }
```

---

## Example: Two Functions

```
Source:
fn square(x: i32) i32 {
    return x * x;
}

fn main() i32 {
    return 0;
}

ZIR:

function "square":
  params: [("x", i32)]
  return_type: i32
  body:
    %0 = param_ref(0)
    %1 = param_ref(0)
    %2 = mul(%0, %1)
    %3 = ret(%2)

function "main":
  params: []
  return_type: i32
  body:
    %0 = constant(0)
    %1 = ret(%0)
```

---

## Void Functions

```
Source:
fn doNothing() void {
    return;
}

ZIR:
function "doNothing":
  params: []
  return_type: void
  body:
    %0 = ret_void()
```

---

## Verify Your Implementation

### Test 1: Simple function
```
Input:  fn f() i32 { return 42; }
ZIR:
    function "f":
      params: []
      return_type: i32
      body:
        %0 = constant(42)
        %1 = ret(%0)
```

### Test 2: With parameters
```
Input:  fn add(a: i32, b: i32) i32 { return a + b; }
ZIR:
    function "add":
      params: [("a", i32), ("b", i32)]
      return_type: i32
      body:
        %0 = param_ref(0)
        %1 = param_ref(1)
        %2 = add(%0, %1)
        %3 = ret(%2)
```

### Test 3: With local variable
```
Input:
fn calc(n: i32) i32 {
    const doubled: i32 = n * 2;
    return doubled;
}

ZIR:
    function "calc":
      params: [("n", i32)]
      return_type: i32
      body:
        %0 = param_ref(0)
        %1 = constant(2)
        %2 = mul(%0, %1)
        %3 = decl("doubled", %2)
        %4 = decl_ref("doubled")
        %5 = ret(%4)
```

### Test 4: Multiple statements
```
Input:
fn compute(x: i32, y: i32) i32 {
    const sum: i32 = x + y;
    const doubled: i32 = sum * 2;
    return doubled;
}

ZIR:
    function "compute":
      params: [("x", i32), ("y", i32)]
      return_type: i32
      body:
        %0 = param_ref(0)
        %1 = param_ref(1)
        %2 = add(%0, %1)
        %3 = decl("sum", %2)
        %4 = decl_ref("sum")
        %5 = constant(2)
        %6 = mul(%4, %5)
        %7 = decl("doubled", %6)
        %8 = decl_ref("doubled")
        %9 = ret(%8)
```

### Test 5: Void function
```
Input:  fn noop() void { return; }
ZIR:
    function "noop":
      params: []
      return_type: void
      body:
        %0 = ret_void()
```

---

## What's Next

Let's put together the complete ZIR generator.

Next: [Lesson 3.7: Complete ZIR](../07-putting-together/) →
