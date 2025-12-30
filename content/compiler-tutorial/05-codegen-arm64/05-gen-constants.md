---
title: "Lesson 5: Generating Constants"
weight: 5
---

# Lesson 5: Generating Constants

Now we start building the code generator! We'll begin with the simplest case: loading constant values into registers.

**What you'll learn:**
- Generating code for small integer literals
- Handling larger integers (>16 bits)
- Negative numbers and booleans

---

## Sub-lesson 5.1: Small Integers

### The Problem

When ZIR has a `literal` instruction, we need to emit ARM64 code to load that value:

```
ZIR:   %0 = literal(42)
ARM64: ???
```

### The Solution

Use the `mov` instruction with an immediate:

```asm
mov     w9, #42         // w9 = 42
```

**Implementation:**

```
generateLiteral(index, value) {
    reg = allocateRegister(index)
    emit("    mov     {}, #{}", reg, value)
}
```

**Examples:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ INTEGER LITERAL GENERATION                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ZIR                      ARM64 Output                              │
│ ───                      ────────────                              │
│ %0 = literal(42)         mov     w9, #42                           │
│ %1 = literal(0)          mov     w10, #0                           │
│ %2 = literal(100)        mov     w11, #100                         │
│ %3 = literal(255)        mov     w12, #255                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**How it works:**

The `mov` instruction with an immediate can encode values directly in the instruction. For small values (0-65535), this is one instruction.

---

## Sub-lesson 5.2: Large Integers

### The Problem

ARM64's `mov` immediate can only encode 16 bits at a time. What about larger values like `100000`?

### The Solution

For values that don't fit in 16 bits, use `movz` (move with zero) and `movk` (move keep):

```
┌─────────────────────────────────────────────────────────────────────┐
│ LARGE INTEGER LOADING                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Values 0-65535 (fits in 16 bits):                                  │
│   mov     w0, #value                                               │
│                                                                     │
│ Values > 65535:                                                     │
│   movz    w0, #low16                   // set low 16 bits          │
│   movk    w0, #high16, lsl #16         // set high 16 bits         │
│                                                                     │
│ Example: 100000 = 0x186A0                                          │
│   low16 = 0x86A0 = 34464                                           │
│   high16 = 0x1 = 1                                                 │
│                                                                     │
│   movz    w0, #34464                   // w0 = 0x000086A0          │
│   movk    w0, #1, lsl #16              // w0 = 0x000186A0          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**For our tutorial:** We'll keep values small (< 65536) so a single `mov` suffices. Real compilers handle larger values.

**Implementation with size check:**

```
generateLiteral(index, value) {
    reg = allocateRegister(index)

    if (value >= 0 && value <= 65535) {
        emit("    mov     {}, #{}", reg, value)
    } else if (value >= -65536 && value < 0) {
        // Negative values - assembler handles this
        emit("    mov     {}, #{}", reg, value)
    } else {
        // Large positive value - need two instructions
        low16 = value & 0xFFFF
        high16 = (value >> 16) & 0xFFFF
        emit("    movz    {}, #{}", reg, low16)
        emit("    movk    {}, #{}, lsl #16", reg, high16)
    }
}
```

---

## Sub-lesson 5.3: Negative Numbers and Booleans

### The Problem

What about negative numbers like `-5`? Computers only have bits (0s and 1s) - how do you represent "negative"?

### The Solution: Two's Complement

Computers use **two's complement** to represent negative numbers. The key idea: negative numbers "wrap around" from the top of the number range.

```
┌─────────────────────────────────────────────────────────────────────┐
│ TWO'S COMPLEMENT (simplified, 8-bit example)                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Think of it like an odometer that wraps around:                    │
│                                                                     │
│     ... -2   -1    0    1    2 ...   (what we mean)                │
│         │    │    │    │    │                                      │
│         ▼    ▼    ▼    ▼    ▼                                      │
│     ...254  255    0    1    2 ...   (what's stored in bits)       │
│                                                                     │
│ So -1 is stored as "all bits set" (255 for 8-bit, 0xFFFFFFFF for  │
│ 32-bit), and -5 is stored as 251 (0xFFFFFFFB for 32-bit).          │
│                                                                     │
│ The clever part: addition just works! The CPU doesn't care if      │
│ you think of 255 as "-1" or "255" - the math is the same.          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**For our code generator:** We don't need to do anything special. The assembler handles it:

```asm
mov     w9, #-5         // Assembler converts to two's complement
mov     w9, #-1         // Becomes 0xFFFFFFFF (all 32 bits set)
```

**Booleans:** Just integers 0 and 1:

```
┌─────────────────────────────────────────────────────────────────────┐
│ BOOLEANS                                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   false → mov  w9, #0                                              │
│   true  → mov  w9, #1                                              │
│                                                                     │
│ ZIR treats booleans as 0/1 literals, so same code path:            │
│   %0 = literal(1)   // true                                        │
│   %1 = literal(0)   // false                                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Unified implementation:**

```
generateLiteral(index, value) {
    reg = allocateRegister(index)
    // Works for positive, negative, and boolean values
    emit("    mov     {}, #{}", reg, value)
}
```

---

## Complete Literal Generation Code

Here's the complete code for handling literals:

```
ARM64Gen {
    output: StringBuilder
    scratch_regs = ["w9", "w10", "w11", "w12", "w13", "w14", "w15"]
    reg_map = {}
    next_reg = 0

    allocateRegister(index) -> string {
        reg = scratch_regs[next_reg]
        reg_map[index] = reg
        next_reg += 1
        return reg
    }

    emit(format, ...args) {
        output.append(format.format(args) + "\n")
    }

    generateLiteral(index, value) {
        reg = allocateRegister(index)
        emit("    mov     {}, #{}", reg, value)
    }
}
```

**Usage:**

```
gen = ARM64Gen.init()

// Generate: %0 = literal(42)
gen.generateLiteral(0, 42)

// Generate: %1 = literal(-5)
gen.generateLiteral(1, -5)

// Generate: %2 = literal(1)  (true)
gen.generateLiteral(2, 1)

// Output:
//     mov     w9, #42
//     mov     w10, #-5
//     mov     w11, #1
```

---

## Summary: Constant Generation

```
┌────────────────────────────────────────────────────────────────────┐
│ ARM64 CONSTANT GENERATION SUMMARY                                  │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ INSTRUCTION:  mov  wN, #value                                      │
│                                                                    │
│ VALUE TYPES:                                                       │
│   Positive:   mov  w9, #42                                        │
│   Zero:       mov  w9, #0                                         │
│   Negative:   mov  w9, #-5                                        │
│   True:       mov  w9, #1                                         │
│   False:      mov  w9, #0                                         │
│                                                                    │
│ LARGE VALUES (>16 bits):                                          │
│   movz  w9, #low16                                                │
│   movk  w9, #high16, lsl #16                                      │
│                                                                    │
│ Compare to x86:                                                   │
│   ARM64: mov  w9, #42     (no prefix on register)                 │
│   x86:   movl $42, %r10d  ($ for immediate, % for register)       │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Create a function that returns a constant:

```bash
cat > const.s << 'EOF'
    .text
    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // %0 = literal(42)
    mov     w9, #42

    // return %0
    mov     w0, w9

    ldp     x29, x30, [sp], #16
    ret
EOF

cc -o const const.s
./const
echo $?  # Should print 42
```

Try negative numbers:

```bash
cat > neg.s << 'EOF'
    .text
    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     w9, #-1         // This will show as 255 (exit codes are 0-255)
    mov     w0, w9

    ldp     x29, x30, [sp], #16
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
