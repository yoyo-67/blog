---
title: "Lesson 9: Complete Backend"
weight: 9
---

# Lesson 9: Complete x86 Backend

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
    .text                   # Begin code section

    .globl add              # Export first function
add:
    # function body...
    ret

    .globl main             # Export second function
main:
    # function body...
    ret
```

**Complete template:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ ASSEMBLY FILE STRUCTURE                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│     .text                         # Code section                    │
│                                                                     │
│     # Function 1                                                    │
│     .globl func1                                                    │
│ func1:                                                              │
│     pushq   %rbp                                                    │
│     movq    %rsp, %rbp                                             │
│     # ... body ...                                                  │
│     popq    %rbp                                                    │
│     ret                                                             │
│                                                                     │
│     # Function 2                                                    │
│     .globl func2                                                    │
│ func2:                                                              │
│     pushq   %rbp                                                    │
│     movq    %rsp, %rbp                                             │
│     # ... body ...                                                  │
│     popq    %rbp                                                    │
│     ret                                                             │
│                                                                     │
│     # ... more functions ...                                        │
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
X86Gen {
    output: StringBuilder
    current_reg_index: int
    reg_map: Map<int, string>

    scratch_regs: ["r10d", "r11d", "r12d", "r13d", "r14d", "r15d"]
    param_regs: ["edi", "esi", "edx", "ecx", "r8d", "r9d"]
}

generate(program) -> string {
    gen = X86Gen.init()
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

    // Header
    emit("    .globl {}", func.name)
    emit("{}:", func.name)

    // Prologue
    emit("    pushq   %rbp")
    emit("    movq    %rsp, %rbp")

    // Generate each instruction
    for index, instruction in func.zir.instructions {
        generateInstruction(index, instruction)
    }
}

generateInstruction(index, instruction) {
    switch instruction {
        literal(value):
            reg = allocateRegister(index)
            emit("    movl    ${}, %{}", value, reg)

        param_ref(param_index):
            src = param_regs[param_index]
            dst = allocateRegister(index)
            emit("    movl    %{}, %{}", src, dst)

        add(lhs, rhs):
            lhs_reg = getRegister(lhs)
            rhs_reg = getRegister(rhs)
            dst = allocateRegister(index)
            emit("    movl    %{}, %{}", lhs_reg, dst)
            emit("    addl    %{}, %{}", rhs_reg, dst)

        sub(lhs, rhs):
            lhs_reg = getRegister(lhs)
            rhs_reg = getRegister(rhs)
            dst = allocateRegister(index)
            emit("    movl    %{}, %{}", lhs_reg, dst)
            emit("    subl    %{}, %{}", rhs_reg, dst)

        mul(lhs, rhs):
            lhs_reg = getRegister(lhs)
            rhs_reg = getRegister(rhs)
            dst = allocateRegister(index)
            emit("    movl    %{}, %{}", lhs_reg, dst)
            emit("    imull   %{}, %{}", rhs_reg, dst)

        div(lhs, rhs):
            lhs_reg = getRegister(lhs)
            rhs_reg = getRegister(rhs)
            dst = allocateRegister(index)
            emit("    movl    %{}, %eax", lhs_reg)
            emit("    cdq")
            emit("    idivl   %{}", rhs_reg)
            emit("    movl    %eax, %{}", dst)

        call(fn_name, args):
            // Set up arguments
            for i, arg in args {
                arg_reg = getRegister(arg)
                emit("    movl    %{}, %{}", arg_reg, param_regs[i])
            }
            // Call
            emit("    call    {}", fn_name)
            // Capture result
            dst = allocateRegister(index)
            emit("    movl    %eax, %{}", dst)

        ret(value):
            value_reg = getRegister(value)
            emit("    movl    %{}, %eax", value_reg)
            emit("    popq    %rbp")
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

**Method 1: Two-step (traditional)**

```bash
# Step 1: Assemble (produces object file)
as -o output.o output.s

# Step 2: Link (produces executable)
ld -o program output.o -lc -dynamic-linker /lib64/ld-linux-x86-64.so.2
# (linking is complex on modern systems)
```

**Method 2: Use cc (recommended)**

```bash
# One step - cc handles assembling and linking
cc -o program output.s

# Run it
./program

# Check exit code
echo $?
```

`cc` (which is usually gcc or clang) knows how to:
- Assemble `.s` files
- Link with the C runtime
- Handle all platform-specific details

**For macOS:**
```bash
cc -o program output.s
./program
```

**For Linux:**
```bash
cc -o program output.s
./program
```

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
  %0 = param_ref(0)    # x
  %1 = mul(%0, %0)     # x * x
  %2 = ret(%1)

Function: add
  %0 = param_ref(0)    # a
  %1 = param_ref(1)    # b
  %2 = add(%0, %1)     # a + b
  %3 = ret(%2)

Function: main
  %0 = literal(5)
  %1 = call(square, [%0])   # square(5)
  %2 = literal(4)
  %3 = call(square, [%2])   # square(4)
  %4 = call(add, [%1, %3])  # add(a, b)
  %5 = ret(%4)
```

**Generated x86 (output.s):**

```asm
    .text

    .globl square
square:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %r10d
    movl    %r10d, %r11d
    imull   %r10d, %r11d
    movl    %r11d, %eax
    popq    %rbp
    ret

    .globl add
add:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %r10d
    movl    %esi, %r11d
    movl    %r10d, %r12d
    addl    %r11d, %r12d
    movl    %r12d, %eax
    popq    %rbp
    ret

    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    $5, %r10d
    movl    %r10d, %edi
    call    square
    movl    %eax, %r11d
    movl    $4, %r12d
    movl    %r12d, %edi
    call    square
    movl    %eax, %r13d
    movl    %r11d, %edi
    movl    %r13d, %esi
    call    add
    movl    %eax, %r14d
    movl    %r14d, %eax
    popq    %rbp
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

## Summary: Complete x86 Backend

```
┌────────────────────────────────────────────────────────────────────┐
│ x86 BACKEND - COMPLETE SUMMARY                                     │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ PIPELINE:                                                          │
│   Source → Lexer → Parser → ZIR → x86 Codegen → .s file → cc      │
│                                                                    │
│ GENERATED CODE STRUCTURE:                                          │
│   .text section                                                    │
│   For each function:                                               │
│     - .globl directive                                             │
│     - Label                                                        │
│     - Prologue: pushq %rbp; movq %rsp, %rbp                       │
│     - Body instructions                                            │
│     - Epilogue + ret                                               │
│                                                                    │
│ REGISTER USAGE:                                                    │
│   Parameters: edi, esi, edx, ecx, r8d, r9d                        │
│   Scratch: r10d, r11d, r12d, r13d, r14d, r15d                     │
│   Return: eax                                                     │
│   Stack: rsp, rbp                                                 │
│                                                                    │
│ BUILD COMMAND:                                                     │
│   cc -o program output.s                                          │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## What You've Accomplished

Congratulations! You've built a complete x86-64 code generator that:

| Feature | Implementation |
|---------|---------------|
| Constants | `movl $value, %reg` |
| Arithmetic | `addl`, `subl`, `imull`, `idivl` |
| Parameters | Copy from edi/esi/etc to scratch |
| Returns | Move to eax, epilogue, ret |
| Calls | Set up args, call, capture result |
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
│        │ x86 Codegen │  ← You built this!                       │
│        └──────┬──────┘                                          │
│               ▼                                                  │
│  .globl add                                                      │
│  add:                                                            │
│      pushq %rbp                                                  │
│      movq  %rsp, %rbp                                           │
│      movl  %edi, %r10d                                          │
│      movl  %esi, %r11d                                          │
│      movl  %r10d, %r12d                                         │
│      addl  %r11d, %r12d                                         │
│      movl  %r12d, %eax                                          │
│      popq  %rbp                                                  │
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

    .globl square
square:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %r10d
    movl    %r10d, %r11d
    imull   %r10d, %r11d
    movl    %r11d, %eax
    popq    %rbp
    ret

    .globl add
add:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %r10d
    movl    %esi, %r11d
    movl    %r10d, %r12d
    addl    %r11d, %r12d
    movl    %r12d, %eax
    popq    %rbp
    ret

    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp

    # a = square(5) = 25
    movl    $5, %edi
    call    square
    movl    %eax, %r10d

    # b = square(4) = 16
    movl    $4, %edi
    call    square
    movl    %eax, %r11d

    # result = add(a, b) = 41
    movl    %r10d, %edi
    movl    %r11d, %esi
    call    add

    popq    %rbp
    ret
EOF

cc -o final final.s
./final
echo $?  # Should print 41
```

---

## Next Steps

You've completed the x86 backend! Here are ideas to explore further:

| Enhancement | Description |
|-------------|-------------|
| Local variables | Use stack slots: `-8(%rbp)`, `-16(%rbp)` |
| If statements | Use `cmpl`, `je`, `jne`, labels |
| Loops | Labels and backward jumps |
| Better register allocation | Reuse registers, linear scan |
| Optimizations | Constant folding, dead code elimination |
| More types | f64 with xmm registers, pointers |

---

## Back to Tutorial

**Return to: [Compiler Tutorial Overview](../../)** →
