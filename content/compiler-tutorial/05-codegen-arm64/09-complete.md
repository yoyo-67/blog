---
title: "Lesson 9: Complete Backend"
weight: 9
---

# Lesson 9: Complete ARM64 Backend

Let's bring everything together into a working code generator that produces real executables.

**What you'll learn:**
- Complete code generator structure
- Assembly file layout
- Building and running your output
- A complete end-to-end example

---

## Sub-lesson 9.1: Assembly File Structure

### The Problem

We've been generating individual pieces. What does a complete assembly file look like?

### The Solution

An assembly file has sections and directives:

```asm
    .text                   // Begin code section

    .globl _add             // Export first function
_add:
    // function body...
    ret

    .globl _main            // Export second function
_main:
    // function body...
    ret
```

**Complete template:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ ASSEMBLY FILE STRUCTURE                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│     .text                         // Code section                   │
│                                                                     │
│     // Function 1                                                   │
│     .globl _func1                                                   │
│ _func1:                                                             │
│     stp     x29, x30, [sp, #-16]!                                  │
│     mov     x29, sp                                                 │
│     // ... body ...                                                 │
│     ldp     x29, x30, [sp], #16                                    │
│     ret                                                             │
│                                                                     │
│     // Function 2                                                   │
│     .globl _func2                                                   │
│ _func2:                                                             │
│     stp     x29, x30, [sp, #-16]!                                  │
│     mov     x29, sp                                                 │
│     // ... body ...                                                 │
│     ldp     x29, x30, [sp], #16                                    │
│     ret                                                             │
│                                                                     │
│     // ... more functions ...                                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Sub-lesson 9.2: The Complete Code Generator

### The Problem

How do we structure the code generator to produce complete output?

### The Solution

Here's the complete code generator:

```
ARM64Gen {
    output: StringBuilder
    current_reg_index: int
    reg_map: Map<int, string>

    scratch_regs: ["w9", "w10", "w11", "w12", "w13", "w14", "w15"]
    param_regs: ["w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7"]
}

generate(program) -> string {
    gen = ARM64Gen.init()
    gen.emit("    .text")
    gen.emit("")

    for func in program.functions {
        gen.generateFunction(func)
        gen.emit("")
    }

    return gen.output.toString()
}

generateFunction(func) {
    // Reset register allocation for each function
    current_reg_index = 0
    reg_map = {}

    // Header (macOS style with underscore)
    emit("    .globl _{}", func.name)
    emit("_{}:", func.name)

    // Prologue
    emit("    stp     x29, x30, [sp, #-16]!")
    emit("    mov     x29, sp")

    // Generate each instruction
    for index, instruction in func.zir.instructions {
        generateInstruction(index, instruction)
    }
}

generateInstruction(index, instruction) {
    switch instruction {
        literal(value):
            reg = allocateRegister(index)
            emit("    mov     {}, #{}", reg, value)

        param_ref(param_index):
            src = param_regs[param_index]
            dst = allocateRegister(index)
            emit("    mov     {}, {}", dst, src)

        add(lhs, rhs):
            lhs_reg = getRegister(lhs)
            rhs_reg = getRegister(rhs)
            dst = allocateRegister(index)
            emit("    add     {}, {}, {}", dst, lhs_reg, rhs_reg)

        sub(lhs, rhs):
            lhs_reg = getRegister(lhs)
            rhs_reg = getRegister(rhs)
            dst = allocateRegister(index)
            emit("    sub     {}, {}, {}", dst, lhs_reg, rhs_reg)

        mul(lhs, rhs):
            lhs_reg = getRegister(lhs)
            rhs_reg = getRegister(rhs)
            dst = allocateRegister(index)
            emit("    mul     {}, {}, {}", dst, lhs_reg, rhs_reg)

        div(lhs, rhs):
            lhs_reg = getRegister(lhs)
            rhs_reg = getRegister(rhs)
            dst = allocateRegister(index)
            emit("    sdiv    {}, {}, {}", dst, lhs_reg, rhs_reg)

        call(fn_name, args):
            // Set up arguments
            for i, arg in args {
                arg_reg = getRegister(arg)
                emit("    mov     {}, {}", param_regs[i], arg_reg)
            }
            // Call
            emit("    bl      _{}", fn_name)
            // Capture result
            dst = allocateRegister(index)
            emit("    mov     {}, w0", dst)

        ret(value):
            value_reg = getRegister(value)
            emit("    mov     w0, {}", value_reg)
            emit("    ldp     x29, x30, [sp], #16")
            emit("    ret")
    }
}

allocateRegister(index) -> string {
    reg = scratch_regs[current_reg_index]
    reg_map[index] = reg
    current_reg_index += 1
    return reg
}

getRegister(index) -> string {
    return reg_map[index]
}

emit(format, ...args) {
    output.append(format.format(args))
    output.append("\n")
}
```

---

## Sub-lesson 9.3: Building and Running

### The Problem

We have an assembly file. How do we turn it into an executable?

### The Solution

**On macOS (Apple Silicon):**

```bash
# Method 1: Use cc (recommended)
cc -o program output.s

# Method 2: Separate steps
as -o output.o output.s
cc -o program output.o

# Run it
./program
echo $?
```

**On Linux ARM64:**

```bash
# Same command works
cc -o program output.s
./program
echo $?
```

**Linux note:** Remember to remove underscore prefixes from labels:
- macOS: `_main`, `_add`
- Linux: `main`, `add`

---

## Sub-lesson 9.4: Complete Example

### End-to-End Compilation

Let's trace a complete program from source to execution:

**Source (program.mini):**

```
fn square(x: i32) i32 {
    return x * x;
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn main() i32 {
    const a = square(5);
    const b = square(4);
    return add(a, b);
}
```

**After parsing and ZIR generation:**

```
Function: square
  %0 = param_ref(0)    // x
  %1 = mul(%0, %0)     // x * x
  %2 = ret(%1)

Function: add
  %0 = param_ref(0)    // a
  %1 = param_ref(1)    // b
  %2 = add(%0, %1)     // a + b
  %3 = ret(%2)

Function: main
  %0 = literal(5)
  %1 = call(square, [%0])   // square(5)
  %2 = literal(4)
  %3 = call(square, [%2])   // square(4)
  %4 = call(add, [%1, %3])  // add(a, b)
  %5 = ret(%4)
```

**Generated ARM64 (output.s):**

```asm
    .text

    .globl _square
_square:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w9, w0              // x
    mul     w10, w9, w9         // x * x
    mov     w0, w10
    ldp     x29, x30, [sp], #16
    ret

    .globl _add
_add:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w9, w0              // a
    mov     w10, w1             // b
    add     w11, w9, w10        // a + b
    mov     w0, w11
    ldp     x29, x30, [sp], #16
    ret

    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w9, #5              // 5
    mov     w0, w9              // arg for square
    bl      _square
    mov     w10, w0             // a = square(5) = 25
    mov     w11, #4             // 4
    mov     w0, w11             // arg for square
    bl      _square
    mov     w12, w0             // b = square(4) = 16
    mov     w0, w10             // first arg (a)
    mov     w1, w12             // second arg (b)
    bl      _add
    mov     w13, w0             // result = 41
    mov     w0, w13
    ldp     x29, x30, [sp], #16
    ret
```

**Build and run:**

```bash
# Compile
cc -o program output.s

# Run
./program
echo $?
# Output: 41 (25 + 16 = 41)
```

---

## Summary: Complete ARM64 Backend

```
┌────────────────────────────────────────────────────────────────────┐
│ ARM64 BACKEND - COMPLETE SUMMARY                                   │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ PIPELINE:                                                          │
│   Source → Lexer → Parser → ZIR → ARM64 Codegen → .s file → cc   │
│                                                                    │
│ GENERATED CODE STRUCTURE:                                          │
│   .text section                                                    │
│   For each function:                                               │
│     - .globl directive                                             │
│     - Label (with _ prefix on macOS)                              │
│     - Prologue: stp x29, x30, [sp, #-16]!; mov x29, sp           │
│     - Body instructions                                            │
│     - Epilogue: ldp x29, x30, [sp], #16; ret                     │
│                                                                    │
│ REGISTER USAGE:                                                    │
│   Parameters: w0, w1, w2, w3, w4, w5, w6, w7                     │
│   Scratch: w9, w10, w11, w12, w13, w14, w15                      │
│   Return: w0                                                      │
│   Frame: x29 (FP), x30 (LR), sp                                  │
│                                                                    │
│ BUILD COMMAND:                                                     │
│   cc -o program output.s                                          │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## What You've Accomplished

Congratulations! You've built a complete ARM64 code generator that:

| Feature | Implementation |
|---------|---------------|
| Constants | `mov wN, #value` |
| Arithmetic | `add`, `sub`, `mul`, `sdiv` (3-operand) |
| Parameters | Copy from w0-w7 to scratch |
| Returns | Move to w0, epilogue, ret |
| Calls | Set up w0-w7, `bl`, capture w0 |
| Functions | Label, prologue, body, epilogue |

**The complete flow:**

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  fn add(a, b) { return a + b; }                                 │
│               │                                                  │
│               ▼                                                  │
│        ┌─────────────┐                                          │
│        │   Lexer     │                                          │
│        └──────┬──────┘                                          │
│               ▼                                                  │
│        ┌─────────────┐                                          │
│        │   Parser    │                                          │
│        └──────┬──────┘                                          │
│               ▼                                                  │
│        ┌─────────────┐                                          │
│        │   ZIR Gen   │                                          │
│        └──────┬──────┘                                          │
│               ▼                                                  │
│        ┌─────────────┐                                          │
│        │ARM64 Codegen│  ← You built this!                       │
│        └──────┬──────┘                                          │
│               ▼                                                  │
│  .globl _add                                                     │
│  _add:                                                           │
│      stp  x29, x30, [sp, #-16]!                                 │
│      mov  x29, sp                                                │
│      mov  w9, w0                                                 │
│      mov  w10, w1                                                │
│      add  w11, w9, w10                                          │
│      mov  w0, w11                                                │
│      ldp  x29, x30, [sp], #16                                   │
│      ret                                                         │
│               │                                                  │
│               ▼                                                  │
│        ┌─────────────┐                                          │
│        │  cc (link)  │                                          │
│        └──────┬──────┘                                          │
│               ▼                                                  │
│        ┌─────────────┐                                          │
│        │ executable  │                                          │
│        └─────────────┘                                          │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Create the final test program:

```bash
cat > final.s << 'EOF'
    .text

    .globl _square
_square:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mul     w0, w0, w0          // x * x, result in w0
    ldp     x29, x30, [sp], #16
    ret

    .globl _add
_add:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    add     w0, w0, w1          // a + b, result in w0
    ldp     x29, x30, [sp], #16
    ret

    .globl _main
_main:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]     // save callee-saved for our values
    mov     x29, sp

    // a = square(5) = 25
    mov     w0, #5
    bl      _square
    mov     w19, w0             // save in callee-saved register

    // b = square(4) = 16
    mov     w0, #4
    bl      _square
    mov     w20, w0             // save in callee-saved register

    // result = add(a, b) = 41
    mov     w0, w19
    mov     w1, w20
    bl      _add

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
EOF

cc -o final final.s
./final
echo $?  # Should print 41
```

---

## Next Steps

You've completed the ARM64 backend! Here are ideas to explore further:

| Enhancement | Description |
|-------------|-------------|
| Local variables | Use stack slots: `[sp, #-8]`, `[sp, #-16]` |
| If statements | Use `cmp`, `b.eq`, `b.ne`, labels |
| Loops | Labels and backward branches |
| Better register allocation | Reuse registers, linear scan |
| Optimizations | Constant folding, dead code elimination |
| More types | i64 with x registers, floats with v registers |

---

## ARM64 vs x86: Final Comparison

| Aspect | ARM64 | x86-64 |
|--------|-------|--------|
| Arithmetic | 3-operand (`add w2, w0, w1`) | 2-operand (`addl %eax, %edx`) |
| Division | Simple (`sdiv w2, w0, w1`) | Complex (needs eax/edx setup) |
| Registers | 31 GPRs | 16 GPRs |
| Call/Return | `bl` + `ret` (uses x30) | `call` + `ret` (uses stack) |
| Syntax | Clean (no prefixes) | AT&T (% and $ prefixes) |

Both backends produce working code - choose based on your target platform!

---

## Back to Tutorial

**Return to: [Compiler Tutorial Overview](../../)** →
