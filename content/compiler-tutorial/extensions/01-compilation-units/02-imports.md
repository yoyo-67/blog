---
title: "1.2: Import Statements"
weight: 2
---

# Lesson 1.2: Import Statements

Let's add the syntax for importing other files.

---

## Goal

Parse import statements like:
```
import "math_utils.mini" as math;
import "utils.mini";  // namespace derived from filename
```

---

## The Import Syntax

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         IMPORT SYNTAX                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   import "path/to/file.mini" as namespace;                                   │
│   ────── ─────────────────── ── ─────────                                    │
│     │           │             │     │                                        │
│     │           │             │     └── identifier (how you'll call it)      │
│     │           │             └── keyword                                    │
│     │           └── string literal (file path)                               │
│     └── keyword                                                              │
│                                                                              │
│   If "as namespace" is omitted, derive from filename:                        │
│   import "math.mini";  →  namespace = "math"                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Add Lexer Tokens

Add these new token types:

```
TokenType = enum {
    // ... existing tokens ...

    kw_import,     // "import"
    kw_as,         // "as"
    string,        // "..." (string literal)
}
```

Add to your keywords map:
```
keywords = {
    "import": kw_import,
    "as":     kw_as,
    // ... existing keywords ...
}
```

---

## Step 2: Add AST Node

Add an import declaration node:

```
Node = union {
    // ... existing nodes ...

    import_decl: ImportDecl,
}

ImportDecl = struct {
    path:      string,   // "math_utils.mini"
    namespace: string,   // "math"
    token:     *Token,   // For error reporting
}
```

---

## Step 3: Parse Import

Add a function to parse import statements:

```
parseImport(allocator) -> Node {
    // Consume 'import' keyword
    token = expect(kw_import)

    // Get the path string
    path_token = expect(string)
    path = strip_quotes(path_token.lexeme)  // Remove surrounding quotes

    // Check for optional 'as namespace'
    if see(kw_as) {
        consume()  // eat 'as'
        namespace = expect(identifier).lexeme
    } else {
        // Derive namespace from filename
        namespace = derive_namespace(path)
    }

    expect(semicolon)

    return Node.import_decl {
        path: path,
        namespace: namespace,
        token: token,
    }
}
```

---

## Step 4: Derive Namespace from Path

When no explicit namespace is given, extract it from the filename:

```
derive_namespace(path) -> string {
    // Get filename from path (after last /)
    filename = path
    if last_index_of(path, "/") is idx {
        filename = path[idx + 1 ..]
    }

    // Remove .mini extension
    if ends_with(filename, ".mini") {
        return filename[0 .. length - 5]
    }

    return filename
}
```

Examples:
- `"math.mini"` → `"math"`
- `"lib/utils.mini"` → `"utils"`
- `"helpers.mini"` → `"helpers"`

---

## Step 5: Update parseNode

Modify your main parsing function to recognize imports:

```
parseNode(allocator) -> Node {
    if see(kw_import) {
        return parseImport(allocator)
    }
    if see(kw_fn) {
        return parseFn(allocator)
    }
    // ... rest of parsing ...
}
```

---

## Verify Your Implementation

### Test 1: Import with explicit namespace
```
Input:  import "math.mini" as m;
Output: ImportDecl { path: "math.mini", namespace: "m" }
```

### Test 2: Import with derived namespace
```
Input:  import "math.mini";
Output: ImportDecl { path: "math.mini", namespace: "math" }
```

### Test 3: Import from subdirectory
```
Input:  import "lib/utils.mini";
Output: ImportDecl { path: "lib/utils.mini", namespace: "utils" }
```

### Test 4: Import with function
```
Input:  import "utils.mini";
        fn main() i32 { return 0; }

Output: Root {
          decls: [
            ImportDecl { path: "utils.mini", namespace: "utils" },
            FnDecl { name: "main", ... }
          ]
        }
```

---

## What's Next

We can parse import statements, but they don't do anything yet. Let's load the imported files.

Next: [Lesson 1.3: Loading Imports](../03-loading-imports/) →
