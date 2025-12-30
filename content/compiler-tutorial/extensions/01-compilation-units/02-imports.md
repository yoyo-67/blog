---
title: "Module 2: Import Statements"
weight: 2
---

# Module 2: Import Statements

Let's add the syntax for importing other files. This module teaches you to extend your lexer and parser to handle import declarations.

**What you'll build:**
- New lexer tokens: `import`, `as`, string literals
- AST node for import declarations
- `parseImport()` function
- Automatic namespace derivation from filenames

---

## Sub-lesson 2.1: Adding New Tokens

### The Problem

Your lexer doesn't recognize the import syntax:

```
import "math.mini" as math;
```

It sees:
- `import` - Unknown identifier? Keyword?
- `"math.mini"` - What's this string thing?
- `as` - Another unknown word?

We need to teach the lexer these new token types.

### The Solution

Add three new token types to your lexer.

**New Token Types:**

```
TokenType = enum {
    // ... existing tokens ...

    kw_import,     // The "import" keyword
    kw_as,         // The "as" keyword
    string,        // String literal: "..."
}
```

**Update Keywords Map:**

```
keywords = {
    "import": kw_import,
    "as":     kw_as,
    "fn":     kw_fn,
    "return": kw_return,
    "if":     kw_if,
    // ... other existing keywords ...
}
```

**Lexing String Literals:**

String literals start and end with double quotes:

```
lexString(self) -> Token {
    start = self.pos
    self.advance()  // Skip opening quote

    while self.current() != '"' and not self.isAtEnd() {
        self.advance()
    }

    if self.isAtEnd() {
        error("Unterminated string")
    }

    self.advance()  // Skip closing quote

    // Lexeme includes quotes: "math.mini"
    return Token {
        type: string,
        lexeme: self.source[start .. self.pos],
        line: self.line,
    }
}
```

**Update Main Lexer Loop:**

```
nextToken(self) -> Token {
    // ... skip whitespace ...

    c = self.current()

    // Check for string literal
    if c == '"' {
        return self.lexString()
    }

    // Check for identifier/keyword
    if isAlpha(c) {
        return self.lexIdentifierOrKeyword()
    }

    // ... rest of lexer ...
}
```

### Try It Yourself

1. Add the three new token types
2. Update your keywords map
3. Implement `lexString()`
4. Test:

```
// Test: Lex import keyword
tokens = lex("import")
assert tokens[0].type == kw_import

// Test: Lex as keyword
tokens = lex("as")
assert tokens[0].type == kw_as

// Test: Lex string literal
tokens = lex('"math.mini"')
assert tokens[0].type == string
assert tokens[0].lexeme == '"math.mini"'

// Test: Complete import statement
tokens = lex('import "math.mini" as math;')
assert tokens[0].type == kw_import
assert tokens[1].type == string
assert tokens[2].type == kw_as
assert tokens[3].type == identifier
assert tokens[4].type == semicolon
```

### What This Enables

Your lexer can now tokenize import statements:

```
import "lib/utils.mini" as utils;

Tokens:
[kw_import] [string:"lib/utils.mini"] [kw_as] [identifier:utils] [semicolon]
```

---

## Sub-lesson 2.2: Import AST Node

### The Problem

We can tokenize imports, but we need a way to represent them in the AST.

```
import "math.mini" as math;

What data do we need to store?
- The file path: "math.mini"
- The namespace: "math"
- Source location for errors
```

### The Solution

Create an `ImportDecl` AST node.

**AST Node Definition:**

```
Node = union {
    // ... existing nodes ...

    import_decl: ImportDecl,
}

ImportDecl = struct {
    path: string      // "math.mini" (without quotes)
    namespace: string // "math"
    token: *Token     // For error reporting
}
```

**Why Store path Without Quotes?**

The lexeme includes quotes: `"math.mini"`
But we store just the path: `math.mini`

This makes it easier to use later (file operations, namespace derivation).

```
┌─────────────────────────────────────────────────────────────────────┐
│ IMPORT AST NODE                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Source: import "lib/math.mini" as m;                                │
│                                                                     │
│ ImportDecl {                                                        │
│     path: "lib/math.mini"    ← Quotes stripped                      │
│     namespace: "m"           ← The alias                            │
│     token: <import token>    ← For "error at line X"                │
│ }                                                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Try It Yourself

1. Add `import_decl` variant to your Node union
2. Create `ImportDecl` struct
3. Test creating nodes:

```
// Test: Create import declaration node
node = Node.import_decl {
    path: "math.mini",
    namespace: "math",
    token: &token,
}

assert node.import_decl.path == "math.mini"
assert node.import_decl.namespace == "math"
```

### What This Enables

You can now represent imports in your AST alongside functions:

```
Root {
    decls: [
        ImportDecl { path: "math.mini", namespace: "math" },
        ImportDecl { path: "utils.mini", namespace: "utils" },
        FnDecl { name: "main", ... },
    ]
}
```

---

## Sub-lesson 2.3: Parsing Import Statements

### The Problem

We have tokens and AST nodes, but we need to connect them. The parser needs to recognize the import syntax:

```
import "path/to/file.mini" as namespace;
```

### The Solution

Add a `parseImport()` function to your parser.

**The Grammar:**

```
import_decl = "import" STRING ("as" IDENTIFIER)? ";"
```

Translation:
- Required: `import` keyword
- Required: string literal (the path)
- Optional: `as` keyword followed by identifier
- Required: semicolon

**Implementation:**

```
parseImport(self, allocator) -> Node {
    // 1. Consume 'import' keyword
    import_token = self.expect(kw_import)

    // 2. Get the path string
    path_token = self.expect(string)

    // 3. Strip quotes from path
    // "math.mini" → math.mini
    path = path_token.lexeme[1 .. path_token.lexeme.len - 1]

    // 4. Check for optional 'as namespace'
    namespace = null
    if self.see(kw_as) {
        self.consume()  // eat 'as'
        namespace = self.expect(identifier).lexeme
    }

    // 5. If no explicit namespace, derive from filename (next sub-lesson)
    if namespace == null {
        namespace = deriveNamespace(path)
    }

    // 6. Expect semicolon
    self.expect(semicolon)

    // 7. Return AST node
    return Node.import_decl {
        path: path,
        namespace: namespace,
        token: import_token,
    }
}
```

**Update Main Parse Function:**

Your main parsing function needs to check for imports:

```
parseDecl(self, allocator) -> Node {
    // Check for import first
    if self.see(kw_import) {
        return self.parseImport(allocator)
    }

    // Check for function
    if self.see(kw_fn) {
        return self.parseFn(allocator)
    }

    // ... other declarations ...
}
```

**Helper Functions:**

```
// Check if current token is of given type
see(self, type) -> bool {
    return self.current().type == type
}

// Consume current token and return it
consume(self) -> Token {
    token = self.current()
    self.advance()
    return token
}

// Expect specific token type, error if not found
expect(self, type) -> Token {
    if not self.see(type) {
        error("Expected {}, got {}", type, self.current().type)
    }
    return self.consume()
}
```

### Try It Yourself

1. Implement `parseImport()`
2. Update your main parse function to recognize imports
3. Test:

```
// Test: Import with explicit namespace
input = 'import "math.mini" as m;'
node = parse(input).decls[0]

assert node.import_decl.path == "math.mini"
assert node.import_decl.namespace == "m"

// Test: Import with function
input = '''
import "utils.mini" as u;
fn main() i32 { return 0; }
'''
root = parse(input)

assert root.decls.len == 2
assert root.decls[0].import_decl.path == "utils.mini"
assert root.decls[1].fn_decl.name == "main"
```

### What This Enables

You can now parse import statements mixed with functions:

```
import "math.mini" as math;
import "utils.mini" as utils;

fn main() i32 {
    return 0;
}
```

Parses to:
```
Root {
    decls: [
        ImportDecl { path: "math.mini", namespace: "math" },
        ImportDecl { path: "utils.mini", namespace: "utils" },
        FnDecl { name: "main", ... },
    ]
}
```

---

## Sub-lesson 2.4: Namespace Derivation

### The Problem

What if the user writes:

```
import "math.mini";
```

Without `as namespace`? We need a default namespace.

The obvious choice: derive it from the filename.

```
"math.mini"        → "math"
"lib/utils.mini"   → "utils"
"helpers.mini"     → "helpers"
```

### The Solution

Implement `deriveNamespace()` to extract the namespace from a file path.

**Algorithm:**

```
deriveNamespace(path) -> string {
    // Step 1: Extract filename from path
    filename = path

    // Find last slash
    if lastIndexOf(path, "/") -> idx {
        filename = path[idx + 1 ..]
    }

    // Step 2: Remove .mini extension
    if endsWith(filename, ".mini") {
        return filename[0 .. filename.len - 5]
    }

    // No extension? Use filename as-is
    return filename
}
```

**Examples:**

```
┌────────────────────────────────────────────────────────────────────┐
│ PATH                    │ FILENAME      │ NAMESPACE               │
├─────────────────────────┼───────────────┼─────────────────────────┤
│ "math.mini"             │ "math.mini"   │ "math"                  │
│ "lib/utils.mini"        │ "utils.mini"  │ "utils"                 │
│ "src/helpers.mini"      │ "helpers.mini"│ "helpers"               │
│ "../shared/io.mini"     │ "io.mini"     │ "io"                    │
│ "noext"                 │ "noext"       │ "noext"                 │
└────────────────────────────────────────────────────────────────────┘
```

**Integration with parseImport:**

```
parseImport(self, allocator) -> Node {
    // ... get path ...

    // Check for optional 'as namespace'
    if self.see(kw_as) {
        self.consume()
        namespace = self.expect(identifier).lexeme
    } else {
        // Derive from filename
        namespace = deriveNamespace(path)
    }

    // ... rest of function ...
}
```

### Try It Yourself

1. Implement `deriveNamespace()`
2. Test derivation:

```
// Test: Simple filename
assert deriveNamespace("math.mini") == "math"

// Test: Path with directory
assert deriveNamespace("lib/utils.mini") == "utils"

// Test: Deep path
assert deriveNamespace("src/core/helpers.mini") == "helpers"

// Test: No extension
assert deriveNamespace("config") == "config"
```

3. Test with parsing:

```
// Test: Import without explicit namespace
input = 'import "math.mini";'
node = parse(input).decls[0]

assert node.import_decl.path == "math.mini"
assert node.import_decl.namespace == "math"  // Derived!

// Test: Import with explicit namespace (overrides derivation)
input = 'import "math.mini" as m;'
node = parse(input).decls[0]

assert node.import_decl.namespace == "m"  // Explicit wins
```

### What This Enables

Users can write concise imports:

```
// Short form - namespace derived from filename
import "math.mini";           // namespace = "math"
import "lib/utils.mini";      // namespace = "utils"

// Long form - explicit namespace
import "math.mini" as m;      // namespace = "m"
import "math.mini" as math;   // namespace = "math"
```

Both forms work and produce proper AST nodes.

---

## Summary: Complete Import Parsing

```
┌────────────────────────────────────────────────────────────────────┐
│ IMPORT PARSING - Complete Implementation                           │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ New Tokens:                                                        │
│   kw_import    - "import" keyword                                  │
│   kw_as        - "as" keyword                                      │
│   string       - String literal "..."                              │
│                                                                    │
│ AST Node:                                                          │
│   ImportDecl {                                                     │
│       path: string       // File path without quotes               │
│       namespace: string  // Explicit or derived                    │
│       token: *Token      // For error messages                     │
│   }                                                                │
│                                                                    │
│ Functions:                                                         │
│   parseImport(allocator) -> Node                                   │
│   deriveNamespace(path) -> string                                  │
│                                                                    │
│ Syntax:                                                            │
│   import "path" as namespace;   // Explicit                        │
│   import "path";                // Derived from filename           │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

We can parse imports, but they don't do anything yet. The imported files aren't loaded. Let's fix that.

**Next: [Module 3: Loading Imports](../03-loading-imports/)** - Load imported files recursively

---

## Complete Code Reference

For a complete implementation, see:
- `src/token.zig` - Token types (`kw_import`, `kw_as`, `string`)
- `src/ast.zig` - `parseImport()`, `deriveNamespace()`
- `src/node.zig` - `import_decl` AST node
