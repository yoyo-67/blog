---
title: "5b.4: Generating Functions"
weight: 4
---

# Lesson 5b.4: Generating Functions

Generate LLVM IR function definitions from AIR.

---

## Goal

Convert AIR function structures to LLVM IR function syntax.

---

## LLVM Function Syntax

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    LLVM FUNCTION SYNTAX                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   define <return_type> @<name>(<param_list>) {                              │
│   <label>:                                                                   │
│       <instructions>                                                         │
│       <terminator>                                                           │
│   }                                                                          │
│                                                                              │
│   Example:                                                                   │
│   ────────                                                                   │
│   define i32 @add(i32 %a, i32 %b) {                                         │
│   entry:                                                                     │
│       %result = add i32 %a, %b                                              │
│       ret i32 %result                                                        │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## AIR to LLVM Function Mapping

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    FUNCTION STRUCTURE MAPPING                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR Function:                    LLVM IR:                                  │
│   ─────────────                    ────────                                  │
│                                                                              │
│   function "multiply":             define i32 @multiply(i32 %p0, i32 %p1) { │
│     params: [I32, I32]             entry:                                   │
│     return_type: I32                   ; instructions here                  │
│     body:                              ret i32 %result                      │
│       %0 = param(0)                }                                        │
│       %1 = param(1)                                                         │
│       %2 = mul_i32(%0, %1)                                                  │
│       %3 = ret(%2)                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Code Generation Steps

```
function generateFunction(airFunc) → string:
    output = ""

    // 1. Function signature
    output += "define "
    output += llvmType(airFunc.return_type)
    output += " @" + airFunc.name + "("

    // 2. Parameters
    for i, paramType in airFunc.params:
        if i > 0: output += ", "
        output += llvmType(paramType) + " %p" + i
    output += ") {\n"

    // 3. Entry block label
    output += "entry:\n"

    // 4. Instructions
    for inst in airFunc.body:
        output += "    " + generateInstruction(inst) + "\n"

    // 5. Close function
    output += "}\n"

    return output
```

---

## Parameter Handling

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARAMETER NAMING                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR uses param indices:          LLVM uses named parameters:               │
│   ───────────────────────          ─────────────────────────                 │
│   %0 = param(0)                    Parameters named %p0, %p1, etc.          │
│   %1 = param(1)                    Or use original names if available        │
│                                                                              │
│   When we see param(N) in AIR, emit %pN in LLVM:                            │
│                                                                              │
│   AIR:  %5 = add_i32(param(0), param(1))                                    │
│   LLVM: %5 = add i32 %p0, %p1                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Example

```
AIR:
    function "square":
        params: [I32]
        return_type: I32
        body:
            %0 = param(0)
            %1 = mul_i32(%0, %0)
            %2 = ret(%1)

Generated LLVM IR:
    define i32 @square(i32 %p0) {
    entry:
        %1 = mul i32 %p0, %p0
        ret i32 %1
    }
```

---

## Void Functions

```
AIR:
    function "doNothing":
        params: []
        return_type: Void
        body:
            %0 = ret_void()

Generated LLVM IR:
    define void @doNothing() {
    entry:
        ret void
    }
```

---

## Multiple Functions

```
AIR:
    function "helper": ...
    function "main": ...

LLVM IR:
    define i32 @helper(i32 %p0) {
    entry:
        ; helper body
    }

    define i32 @main() {
    entry:
        ; main body
    }
```

Functions are emitted in order. LLVM doesn't require forward declarations for functions defined in the same module.

---

## Function Attributes (Optional)

LLVM supports function attributes for optimization hints:

```llvm
; Common attributes
define i32 @pure_function(i32 %x) readonly {    ; No side effects
    ...
}

define void @no_return() noreturn {              ; Never returns
    ...
}

define i32 @fast(i32 %x) nounwind {             ; Won't throw
    ...
}
```

We won't use these in our simple compiler, but they're useful to know about.

---

## Pseudocode Implementation

```
struct LLVMCodegen:
    output: StringBuilder

    fn generateFunction(self, func: AirFunction) void:
        // Signature
        self.emit("define ")
        self.emitType(func.return_type)
        self.emit(" @")
        self.emit(func.name)
        self.emit("(")

        // Parameters
        for i, param in func.params.enumerate():
            if i > 0: self.emit(", ")
            self.emitType(param.type)
            self.emit(" %p")
            self.emitInt(i)

        self.emit(") {\n")
        self.emit("entry:\n")

        // Body
        for inst in func.instructions:
            self.emit("    ")
            self.generateInstruction(inst)
            self.emit("\n")

        self.emit("}\n\n")
```

---

## Verify Your Understanding

### Question 1
What label do we use for the first basic block?

Answer: `entry:` - it's the conventional name for a function's entry point.

### Question 2
How do we name the first parameter in LLVM IR?

Answer: `%p0` (or any name we choose, like `%a`). We use `%pN` for parameter N.

---

## What's Next

Let's generate the actual LLVM instructions.

Next: [Lesson 5b.5: Generating Instructions](../05-gen-instructions/) →
