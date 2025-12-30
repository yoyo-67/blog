---
title: "Lesson 5: Generating Constants"
weight: 5
---

# Lesson 5: Generating Constants

Now we start building the code generator! We'll begin with the simplest case: loading constant values into registers.

**What you'll learn:**
- Generating code for integer literals
- Handling negative numbers
- Boolean values in x86

---

## Sub-lesson 5.1: Integer Literals

### The Problem

When ZIR has a `literal` instruction, we need to emit x86 that puts that value in a register:

```
ZIR:   %0 = literal(42)
x86:   ???
```

### The Solution

Use the `movl` instruction with an immediate (constant) operand:

```asm
movl    $42, %r10d      # r10d = 42
```

**Implementation:**

```
generateInstruction(index, instruction) {
    reg = allocateRegister(index)

    if instruction is literal {
        value = instruction.value
        emit("    movl    ${}, %{}", value, reg)
    }
}
```

**Examples:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ INTEGER LITERAL GENERATION                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ZIR                      x86 Output                                 │
│ ───                      ──────────                                 │
│ %0 = literal(42)         movl    $42, %r10d                        │
│ %1 = literal(0)          movl    $0, %r11d                         │
│ %2 = literal(100)        movl    $100, %r12d                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Sub-lesson 5.2: Negative Numbers

### The Problem

What about negative numbers like `-5`? Computers only have bits (0s and 1s). How do you represent "negative"?

### The Solution: Two's Complement

Computers use a clever system called **two's complement** to represent negative numbers. Here's how it works:

```
┌─────────────────────────────────────────────────────────────────────┐
│ TWO'S COMPLEMENT: HOW NEGATIVE NUMBERS WORK                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ For an 8-bit number (to keep it simple):                           │
│                                                                     │
│   Positive numbers use the obvious binary:                         │
│     0  = 00000000                                                  │
│     1  = 00000001                                                  │
│     5  = 00000101                                                  │
│     127 = 01111111  (largest positive)                             │
│                                                                     │
│   Negative numbers "wrap around" from the top:                     │
│     -1  = 11111111  (all bits set)                                 │
│     -2  = 11111110                                                 │
│     -5  = 11111011                                                 │
│     -128 = 10000000  (most negative)                               │
│                                                                     │
│ Think of it like a car odometer that wraps:                        │
│                                                                     │
│         ... -3  -2  -1   0   1   2   3 ...                        │
│             │   │   │   │   │   │   │                              │
│             ▼   ▼   ▼   ▼   ▼   ▼   ▼                              │
│         ...253 254 255   0   1   2   3...  (as unsigned bytes)     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Why is this clever?** Addition just works! The CPU doesn't need separate "add" and "subtract negative" operations:

```
  5 + (-3) = 2

  In binary (8-bit):
    00000101  (5)
  + 11111101  (-3, which is 253 as unsigned)
  ──────────
    00000010  (2) ← Correct! The overflow bit is discarded.
```

**For our code generator:** We don't need to do anything special. The assembler handles it:

```asm
movl    $-5, %r10d      # Assembler converts -5 to two's complement
movl    $-1, %r11d      # -1 becomes 0xFFFFFFFF (all 32 bits set)
```

**What the assembler does internally:**
- `$-1` → `$0xFFFFFFFF` (all bits set)
- `$-5` → `$0xFFFFFFFB`

**Our code generator just emits the number as-is:**

```
if instruction is literal {
    value = instruction.value    # could be -5
    emit("    movl    ${}, %{}", value, reg)  # emits: movl $-5, %r10d
}
```

**Example:**

```
Source:     return -42;

ZIR:        %0 = literal(-42)
            %1 = ret(%0)

x86:        movl    $-42, %r10d
            movl    %r10d, %eax
            ret
```

---

## Sub-lesson 5.3: Boolean Values

### The Problem

Our language has `true` and `false`. How do we represent them in x86?

### The Solution

Booleans are just integers: `false` = 0, `true` = 1.

```
┌─────────────────────────────────────────────────────────────────────┐
│ BOOLEAN REPRESENTATION                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Source      ZIR                 x86                                 │
│ ──────      ───                 ───                                 │
│ true        literal(1)          movl $1, %r10d                     │
│ false       literal(0)          movl $0, %r10d                     │
│                                                                     │
│ By the time we reach codegen, booleans are already 0 or 1          │
│ in the ZIR literal instruction.                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Our code generator treats them identically to integers:**

```
// This handles all literal types uniformly
if instruction is literal {
    value = instruction.value    // 0, 1, 42, -5, etc.
    emit("    movl    ${}, %{}", value, reg)
}
```

---

## Complete Literal Generation Code

Here's the complete code for handling literals:

```
X86Gen {
    output: StringBuilder
    reg_index: int
    scratch_regs: ["r10d", "r11d", "r12d", "r13d", "r14d", "r15d"]

    allocateRegister(index) -> string {
        return scratch_regs[index]
    }

    emit(format, ...args) {
        output.appendFormat(format + "\n", args)
    }

    generateLiteral(index, value) {
        reg = allocateRegister(index)
        emit("    movl    ${}, %{}", value, reg)
    }
}
```

**Usage:**

```
gen = X86Gen.init()

// Generate: %0 = literal(42)
gen.generateLiteral(0, 42)

// Generate: %1 = literal(-5)
gen.generateLiteral(1, -5)

// Generate: %2 = literal(1)  (true)
gen.generateLiteral(2, 1)

// Output:
//     movl    $42, %r10d
//     movl    $-5, %r11d
//     movl    $1, %r12d
```

---

## Summary: Constant Generation

```
┌────────────────────────────────────────────────────────────────────┐
│ CONSTANT GENERATION SUMMARY                                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ INSTRUCTION:  movl $immediate, %register                           │
│                                                                    │
│ VALUE TYPES:                                                       │
│   Positive integers:  movl $42, %r10d                             │
│   Zero:               movl $0, %r10d                              │
│   Negative integers:  movl $-5, %r10d                             │
│   Boolean true:       movl $1, %r10d                              │
│   Boolean false:      movl $0, %r10d                              │
│                                                                    │
│ All types use the same instruction - the assembler handles        │
│ encoding differences.                                              │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Create a function that returns a constant:

```bash
cat > const.s << 'EOF'
    .text
    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp

    # %0 = literal(42)
    movl    $42, %r10d

    # return %0
    movl    %r10d, %eax

    popq    %rbp
    ret
EOF

cc -o const const.s
./const
echo $?  # Should print 42
```

Now try with a negative number:

```bash
cat > neg.s << 'EOF'
    .text
    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    $-1, %r10d      # This will become 255 as exit code
    movl    %r10d, %eax
    popq    %rbp
    ret
EOF

cc -o neg neg.s
./neg
echo $?  # Prints 255 (exit codes are unsigned 0-255)
```

---

## What's Next

We can generate constants. Now let's add arithmetic operations: add, subtract, multiply, divide.

**Next: [Lesson 6: Generating Arithmetic](../06-gen-arithmetic/)** →
