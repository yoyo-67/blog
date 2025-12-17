---
title: "2.1: AST Nodes"
weight: 1
---

# Lesson 2.1: AST Node Types

Before parsing, we need to define what our tree looks like.

---

## Goal

Define data structures for AST nodes that can represent any valid program.

---

## What is an AST?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        ABSTRACT SYNTAX TREE                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   "Abstract" = We ignore concrete syntax details                             │
│                                                                              │
│   Source:    ( 3 + 5 )        Tokens have parentheses                       │
│   AST:       Add(3, 5)        Tree doesn't - structure is implicit!         │
│                                                                              │
│   The tree captures MEANING, not exact syntax.                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Node Categories

Our AST needs nodes for three categories:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           AST NODE CATEGORIES                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. EXPRESSIONS - Things that produce values                               │
│      • Number literal:    42                                                │
│      • Identifier:        x, foo, myVar                                     │
│      • Unary operation:   -x                                                │
│      • Binary operation:  a + b                                             │
│      • Grouped:           (expr)  - represented as just the inner expr     │
│                                                                              │
│   2. STATEMENTS - Things that do something                                  │
│      • Variable decl:     const x = 5;                                      │
│      • Return:            return x;                                         │
│                                                                              │
│   3. DECLARATIONS - Top-level definitions                                   │
│      • Function:          fn name(...) { ... }                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Expression Nodes

```
// Number literal
NumberExpr {
    value: integer
}

// Variable reference
IdentifierExpr {
    name: string
}

// Unary operation: -x
UnaryExpr {
    operator: Token        // MINUS
    operand: Expression
}

// Binary operation: a + b
BinaryExpr {
    left: Expression
    operator: Token        // PLUS, MINUS, STAR, SLASH
    right: Expression
}
```

---

## Statement Nodes

```
// Variable declaration: const x: i32 = 5;
VarDecl {
    name: string
    type: TypeExpr         // Optional in some languages
    value: Expression
    is_const: boolean      // const vs var
}

// Return statement: return x;
ReturnStmt {
    value: Expression      // Can be null for void functions
}
```

---

## Declaration Nodes

```
// Function: fn add(a: i32, b: i32) i32 { ... }
FnDecl {
    name: string
    params: Parameter[]
    return_type: TypeExpr
    body: Block
}

// Parameter
Parameter {
    name: string
    type: TypeExpr
}

// Block: { stmt; stmt; }
Block {
    statements: Statement[]
}
```

---

## Type Expressions

```
// Simple type reference: i32, bool, void
TypeExpr {
    name: string           // "i32", "bool", "void"
}
```

For our mini compiler, types are just names. A real compiler would have a richer type system.

---

## The Root

```
// The entire program
Root {
    declarations: Declaration[]
}
```

---

## Complete Node Types

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         ALL AST NODE TYPES                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   EXPRESSIONS:                                                               │
│     NumberExpr     { value }                                                │
│     IdentifierExpr { name }                                                 │
│     UnaryExpr      { operator, operand }                                    │
│     BinaryExpr     { left, operator, right }                                │
│                                                                              │
│   STATEMENTS:                                                               │
│     VarDecl        { name, type, value, is_const }                         │
│     ReturnStmt     { value }                                                │
│                                                                              │
│   DECLARATIONS:                                                             │
│     FnDecl         { name, params, return_type, body }                     │
│                                                                              │
│   OTHER:                                                                    │
│     Root           { declarations }                                         │
│     Block          { statements }                                           │
│     Parameter      { name, type }                                           │
│     TypeExpr       { name }                                                 │
│                                                                              │
│   Total: ~10 node types                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Notes

### Option A: Tagged Union
```
Node = {
    tag: NodeType,
    data: (NumberExpr | IdentifierExpr | BinaryExpr | ...)
}
```

### Option B: Class Hierarchy
```
abstract class Node
class NumberExpr extends Node
class BinaryExpr extends Node
// etc.
```

### Option C: Discriminated Union (TypeScript)
```
type Expr =
    | { kind: "number", value: number }
    | { kind: "identifier", name: string }
    | { kind: "binary", left: Expr, op: string, right: Expr }
```

Choose based on your implementation language.

---

## Verify Your Implementation

Create AST nodes manually and verify they can represent these programs:

### Test 1: Number
```
Source: 42
AST:    NumberExpr { value: 42 }
```

### Test 2: Binary expression
```
Source: 3 + 5
AST:    BinaryExpr {
            left: NumberExpr { value: 3 },
            operator: PLUS,
            right: NumberExpr { value: 5 }
        }
```

### Test 3: Nested expression
```
Source: 1 + 2 + 3
AST:    BinaryExpr {
            left: BinaryExpr {
                left: NumberExpr { value: 1 },
                operator: PLUS,
                right: NumberExpr { value: 2 }
            },
            operator: PLUS,
            right: NumberExpr { value: 3 }
        }
```

### Test 4: Variable declaration
```
Source: const x: i32 = 42;
AST:    VarDecl {
            name: "x",
            type: TypeExpr { name: "i32" },
            value: NumberExpr { value: 42 },
            is_const: true
        }
```

---

## What's Next

Now that we can represent trees, let's start building them by parsing simple atoms.

Next: [Lesson 2.2: Atoms](../02-atoms/) →
