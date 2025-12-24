# Semantic Analysis (Sema) Implementation Guide

## Overview

Semantic analysis validates that the code makes sense beyond just syntax. The parser checks structure, sema checks meaning.

```
Source Code → Lexer → Tokens → Parser → AST → ZIR Generator → ZIR → Sema → Errors
```

## Mental Model

### The Pointer Chain

The key insight is that errors need to point back to source locations. Instead of copying location data at each level, we maintain a pointer chain:

```
Error
  └── points to → Instruction (ZIR)
                    └── points to → Node (AST)
                                      └── points to → Token
                                                        └── has line, col
```

When formatting an error, we follow the chain:
```
error.inst.node.token.line  →  gives us the line number
error.inst.node.token.col   →  gives us the column
```

### Why Pointers?

1. **Single source of truth** - location lives only in Token
2. **Rich context** - from an error, you can access the full instruction, node, and token
3. **Extensibility** - add file path to Token later, all errors get it for free

---

## Required Changes to Other Files

### 1. token.zig

Token must have location:

```zig
pub const Token = struct {
    type: Type,
    lexeme: []const u8,
    line: usize,    // ← add
    col: usize,     // ← add
};
```

### 2. lexer.zig

Lexer must:
- Track line/column as it scans
- Populate line/col when creating tokens

```
// In advance():
if current char is '\n':
    line += 1
    column = 1
else:
    column += 1

// In makeToken():
return Token{
    .type = ...,
    .lexeme = ...,
    .line = self.line,
    .col = self.column - token_length,
}
```

### 3. node.zig (AST)

Nodes that can cause errors need a pointer to their token:

```zig
binary_op: struct {
    lhs: *const Node,
    op: Op,
    rhs: *const Node,
    token: *const Token,  // ← add (points to operator token)
},

identifier: struct {
    name: []const u8,
    value: *const Node,
    token: *const Token,  // ← add (points to name token)
},

identifier_ref: struct {
    name: []const u8,
    token: *const Token,  // ← add (points to name token)
},
```

### 4. ast.zig (Parser)

`consume()` should return `*const Token` (pointer to arena memory, not a copy):

```zig
fn consume(self: *Ast) *const Token {
    const token = &self.tokens[self.pos];
    self.advance();
    return token;
}
```

Then usage is simple:
```zig
const token = self.consume();
return .{ .identifier_ref = .{
    .name = token.lexeme,
    .token = token
}};
```

### 5. zir.zig

Instructions that can cause errors need a pointer to their AST node:

```zig
pub const Instruction = union(enum) {
    constant: i32,

    add: struct {
        lhs: u32,
        rhs: u32,
        node: *const Node,  // ← add
    },

    decl: struct {
        name: []const u8,
        value: u32,
        node: *const Node,  // ← add
    },

    decl_ref: struct {
        name: []const u8,
        node: *const Node,  // ← add
    },

    // ... similar for sub, mul, div
};
```

The `generate` function must:
- Take `*const Node` instead of `Node`
- Store the node pointer in instructions

```zig
pub fn generate(self: *Zir, allocator: Allocator, node: *const Node) !u32 {
    switch (node.*) {
        .identifier_ref => |val| {
            return self.emit(.{ .decl_ref = .{
                .name = val.name,
                .node = node   // ← store the pointer
            }});
        },
        // ...
    }
}
```

---

## Sema Implementation

### Data Structures

```zig
pub const Error = union(enum) {
    undefined_variable: struct {
        name: []const u8,
        inst: *const Instruction
    },
    duplicate_declaration: struct {
        name: []const u8,
        inst: *const Instruction
    },
    type_mismatch: struct {
        lhs: []const u8,
        rhs: []const u8,
        inst: *const Instruction
    },
};
```

### Pseudo Code

```
function analyzeProgram(program):
    errors = []

    for each function in program:
        function_errors = analyzeFunction(function)
        errors.append(function_errors)

    return errors


function analyzeFunction(func):
    errors = []

    # Track declared names and their types
    names = HashMap<string, type>

    # Track each instruction's result type (by index)
    inst_types = []

    # Register function parameters
    for each param in func.params:
        names[param.name] = param.type

    # Analyze each instruction
    for i in 0..func.instruction_count():
        inst = func.instruction_at(i)  # get pointer

        result_type = switch inst:

            .constant =>
                "i32"  # literals are i32

            .param_ref(idx) =>
                func.params[idx].type

            .decl(d) =>
                if names.contains(d.name):
                    errors.add(duplicate_declaration(d.name, inst))
                else:
                    value_type = inst_types[d.value]
                    names[d.name] = value_type
                null  # declarations don't produce a value

            .decl_ref(d) =>
                if not names.contains(d.name):
                    errors.add(undefined_variable(d.name, inst))
                    null
                else:
                    names[d.name]  # return the type

            .add(bin), .sub(bin), .mul(bin), .div(bin) =>
                lhs_type = inst_types[bin.lhs]
                rhs_type = inst_types[bin.rhs]

                if lhs_type != rhs_type:
                    errors.add(type_mismatch(lhs_type, rhs_type, inst))
                    null
                else:
                    lhs_type  # result has same type as operands

            .return_stmt =>
                null  # returns don't produce a value

        inst_types.append(result_type)

    return errors
```

### Error Formatting

```
function error.toString(source):
    token = getToken()  # follow pointer chain
    message = getMessage()
    line_content = extractLine(source, token.line)
    caret = makeCaretLine(token.col)

    return "{line}:{col}: error: {message}\n{line_content}\n{caret}\n"


function getToken():
    switch self:
        .undefined_variable(e) => e.inst.decl_ref.node.identifier_ref.token
        .duplicate_declaration(e) => e.inst.decl.node.identifier.token
        .type_mismatch(e) => e.inst.{add,sub,mul,div}.node.binary_op.token


function extractLine(source, line_num):
    # Find the start and end of the requested line
    current_line = 1
    line_start = 0

    for i, char in source:
        if current_line == line_num:
            # Find end of line
            line_end = find '\n' or end of source
            return source[line_start..line_end]

        if char == '\n':
            current_line += 1
            line_start = i + 1

    return ""


function makeCaretLine(col):
    return " " * (col - 1) + "^"
```

---

## The Flow

```
1. Source: "fn foo() { return x; }"

2. Lexer creates tokens with line/col:
   Token{ type: .identifier, lexeme: "x", line: 1, col: 19 }

3. Parser creates AST nodes pointing to tokens:
   Node.identifier_ref{ name: "x", token: → Token }

4. ZIR generator creates instructions pointing to nodes:
   Instruction.decl_ref{ name: "x", node: → Node }

5. Sema analyzes, finds "x" not declared, creates error:
   Error.undefined_variable{ name: "x", inst: → Instruction }

6. Error formatting follows the chain:
   Error → Instruction → Node → Token → (line: 1, col: 19)

   Output:
   1:19: error: undefined variable "x"
   fn foo() { return x; }
                     ^
```

---

## Checklist

- [ ] Token has line/col fields
- [ ] Lexer tracks and populates line/col
- [ ] AST nodes have token pointers (for error-prone nodes)
- [ ] Parser stores token pointers in nodes
- [ ] ZIR instructions have node pointers (for error-prone instructions)
- [ ] ZIR generate() takes *const Node and stores pointers
- [ ] Error variants have instruction pointers
- [ ] Error.toString() follows the pointer chain
- [ ] Helper: getLine(source, line_num)
- [ ] Helper: makeCaretLine(col)
- [ ] errorsToString() takes source and passes to each error

---

## What Sema Checks

1. **Undefined variables** - using a name that was never declared
2. **Duplicate declarations** - declaring the same name twice in same scope
3. **Type mismatches** - operations on incompatible types (i32 + i64)

Future extensions:
- Return type checking
- Function call argument validation
- Shadowing rules
- Scope analysis (nested blocks)
