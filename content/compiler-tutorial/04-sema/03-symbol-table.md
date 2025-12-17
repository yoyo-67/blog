---
title: "4.3: Symbol Table"
weight: 3
---

# Lesson 4.3: Symbol Table

Track all declared names and their properties.

---

## Goal

Build a symbol table that maps names to their declarations.

---

## What Is a Symbol Table?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SYMBOL TABLE                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   A map from names to information about them:                               │
│                                                                              │
│   "x" → { type: I32, kind: LOCAL, slot: 0 }                                │
│   "y" → { type: I64, kind: LOCAL, slot: 1 }                                │
│   "a" → { type: I32, kind: PARAM, index: 0 }                               │
│   "b" → { type: I32, kind: PARAM, index: 1 }                               │
│                                                                              │
│   Given a name, we can find:                                                │
│   - Its type (for type checking)                                            │
│   - Its kind (parameter vs local variable)                                  │
│   - Its location (slot number or parameter index)                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Symbol Entry

```
enum SymbolKind {
    PARAM,      // Function parameter
    LOCAL,      // Local variable (const or var)
}

Symbol {
    name: string,
    type: Type,
    kind: SymbolKind,
    index: integer,     // Param index or local slot
    is_const: boolean,  // Can it be reassigned?
}
```

---

## Symbol Table

```
SymbolTable {
    symbols: Map<string, Symbol>
    next_local_slot: integer

    // Methods
    declareParam(name, type, index)
    declareLocal(name, type, is_const) → slot
    lookup(name) → Symbol or null
    isDeclared(name) → boolean
}
```

---

## Declare Parameter

```
function declareParam(name, type, index):
    if isDeclared(name):
        error("'" + name + "' is already declared")
        return

    symbols[name] = Symbol {
        name: name,
        type: type,
        kind: PARAM,
        index: index,
        is_const: true   // Parameters can't be reassigned
    }
```

---

## Declare Local

```
function declareLocal(name, type, is_const) → integer:
    if isDeclared(name):
        error("'" + name + "' is already declared")
        return -1

    slot = next_local_slot
    next_local_slot = next_local_slot + 1

    symbols[name] = Symbol {
        name: name,
        type: type,
        kind: LOCAL,
        index: slot,
        is_const: is_const
    }

    return slot
```

---

## Lookup

```
function lookup(name) → Symbol or null:
    if name in symbols:
        return symbols[name]
    return null

function isDeclared(name) → boolean:
    return name in symbols
```

---

## Initialize for Function

When analyzing a function, populate parameters first:

```
function initSymbolTable(fn_zir) → SymbolTable:
    table = SymbolTable {
        symbols: {},
        next_local_slot: 0
    }

    // Add all parameters
    for i, param in enumerate(fn_zir.params):
        param_type = resolveType(param.type)
        table.declareParam(param.name, param_type, i)

    return table
```

---

## Example

```
Source:
fn add(a: i32, b: i32) i32 {
    const result: i32 = a + b;
    return result;
}

After initialization (params):
    symbols = {
        "a": { type: I32, kind: PARAM, index: 0 },
        "b": { type: I32, kind: PARAM, index: 1 },
    }
    next_local_slot = 0

After processing const result:
    symbols = {
        "a": { type: I32, kind: PARAM, index: 0 },
        "b": { type: I32, kind: PARAM, index: 1 },
        "result": { type: I32, kind: LOCAL, index: 0 },
    }
    next_local_slot = 1
```

---

## Using the Symbol Table

When analyzing ZIR:

```
function analyzeInstruction(instr, symbol_table):
    switch instr.tag:

        DECL:
            // Get value type first
            value_type = type_of[instr.data.value]

            // Declare the variable
            slot = symbol_table.declareLocal(
                instr.data.name,
                value_type,
                true  // const
            )

            // Record the slot for code generation
            return slot

        DECL_REF:
            symbol = symbol_table.lookup(instr.data.name)
            if symbol == null:
                error("Undefined variable: " + instr.data.name)
                return null

            return symbol  // Contains type, kind, index

        PARAM_REF:
            // We already know parameter types from function signature
            // But we could also look them up by index
            ...
```

---

## Handling Scopes (Future Extension)

For nested blocks, you'd want scope stacking:

```
{
    const x: i32 = 1;
    {
        const x: i32 = 2;   // Different x, shadows outer
        return x;            // Returns 2
    }
    return x;                // Returns 1
}
```

For our mini compiler, we'll have one flat scope per function (simpler).

---

## Verify Your Implementation

### Test 1: Declare and lookup parameter
```
table = SymbolTable()
table.declareParam("a", I32, 0)
sym = table.lookup("a")
assert sym.type == I32
assert sym.kind == PARAM
assert sym.index == 0
```

### Test 2: Declare and lookup local
```
table = SymbolTable()
slot = table.declareLocal("x", I32, true)
assert slot == 0
sym = table.lookup("x")
assert sym.type == I32
assert sym.kind == LOCAL
assert sym.index == 0
```

### Test 3: Undefined lookup
```
table = SymbolTable()
sym = table.lookup("undefined")
assert sym == null
```

### Test 4: Duplicate declaration
```
table = SymbolTable()
table.declareLocal("x", I32, true)
table.declareLocal("x", I32, true)  // Should error!
```

### Test 5: Parameter and local
```
table = SymbolTable()
table.declareParam("a", I32, 0)
table.declareLocal("x", I64, true)

sym_a = table.lookup("a")
assert sym_a.kind == PARAM
assert sym_a.index == 0

sym_x = table.lookup("x")
assert sym_x.kind == LOCAL
assert sym_x.index == 0  // First local slot
```

---

## What's Next

Use the symbol table to resolve name references in ZIR.

Next: [Lesson 4.4: Resolve Names](../04-resolve-names/) →
