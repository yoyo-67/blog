---
title: "Lesson 1: Why ARM64?"
weight: 1
---

# Lesson 1: Why ARM64?

Before we start generating ARM64 assembly, let's understand what ARM64 is, where it runs, and why it's worth learning.

**What you'll learn:**
- What ARM64/AArch64 is and how it differs from x86
- Where ARM64 processors are used
- Trade-offs between ARM64 and x86 backends
- The assembly syntax we'll use

---

## Sub-lesson 1.1: What is ARM64?

### The Problem

You've heard of ARM processors in phones and Apple Silicon Macs. But what actually makes ARM different from x86, and why does it matter for code generation?

### The Solution

ARM64 (also called AArch64) is a 64-bit **RISC** architecture, while x86-64 is a **CISC** architecture:

```
┌─────────────────────────────────────────────────────────────────────┐
│ RISC vs CISC                                                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ RISC (ARM64):                                                       │
│   - Simple, uniform instructions                                    │
│   - Fixed instruction size (4 bytes)                               │
│   - More registers (31 general purpose)                            │
│   - Load/store architecture                                         │
│   - 3-operand instructions: add dst, src1, src2                    │
│                                                                     │
│ CISC (x86):                                                         │
│   - Complex, variable-length instructions (1-15 bytes)             │
│   - Fewer registers (16 general purpose)                           │
│   - Can operate directly on memory                                 │
│   - 2-operand instructions: addl src, dst                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**For code generation, this means:**

| Aspect | ARM64 | x86-64 |
|--------|-------|--------|
| Instructions | Simpler, more uniform | Complex, many special cases |
| Division | Just `sdiv dst, a, b` | Needs eax/edx setup, then `idivl` |
| Arithmetic | `add w0, w1, w2` (3 operands) | `addl %src, %dst` (2 operands, modifies dst) |
| Registers | 31 GPRs | 16 GPRs |

**ARM64 is often easier to generate code for** because instructions are more regular.

---

## Sub-lesson 1.2: Where Does ARM64 Run?

### The Problem

Is ARM64 common enough to bother learning? What systems actually use it?

### The Solution

ARM64 is everywhere:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ARM64 PLATFORMS                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ DESKTOP / LAPTOP:                                                   │
│   ├── Apple Silicon Macs (M1, M2, M3, M4) - since 2020             │
│   ├── Windows on ARM laptops (Surface Pro X, etc.)                 │
│   └── Linux ARM desktops (rare but growing)                        │
│                                                                     │
│ SERVERS:                                                            │
│   ├── AWS Graviton (popular for cloud computing)                   │
│   ├── Ampere Altra                                                 │
│   ├── Oracle Cloud ARM instances                                   │
│   └── Google Cloud Tau T2A                                         │
│                                                                     │
│ SINGLE-BOARD COMPUTERS:                                             │
│   ├── Raspberry Pi 4 and 5 (64-bit mode)                          │
│   ├── Pine64, Rock64                                               │
│   └── NVIDIA Jetson                                                │
│                                                                     │
│ MOBILE:                                                             │
│   ├── All iPhones (since iPhone 5s, 2013)                         │
│   ├── All iPads                                                    │
│   └── Most Android phones                                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Check your system:**

```bash
uname -m
# arm64 or aarch64 → ARM64 system
# x86_64 → Intel/AMD system
```

On macOS:
```bash
# Check if Apple Silicon
sysctl -n machdep.cpu.brand_string
# "Apple M1" or "Apple M2" etc. → ARM64
# "Intel(R) Core(TM)..." → x86
```

---

## Sub-lesson 1.3: ARM64 vs x86 Trade-offs

### The Problem

Should you target ARM64, x86, or both? What are the trade-offs?

### The Solution

**Choose ARM64 when:**
- Running on Apple Silicon Mac (native performance)
- Deploying to ARM servers (AWS Graviton is cost-effective)
- Building for Raspberry Pi
- Learning - ARM64 is more regular and easier to understand

**Choose x86 when:**
- Running on Intel/AMD hardware
- Need maximum compatibility with existing systems
- Building for Windows (most Windows PCs are x86)

**For this tutorial:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHY ARM64 FOR LEARNING?                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ 1. Cleaner instruction set                                          │
│    - 3-operand format is intuitive                                 │
│    - No weird special cases (like x86 division)                    │
│                                                                     │
│ 2. More registers                                                   │
│    - Less worry about running out                                  │
│    - Simpler register allocation                                   │
│                                                                     │
│ 3. Growing ecosystem                                                │
│    - Apple Silicon is mainstream                                   │
│    - ARM servers are increasingly popular                          │
│                                                                     │
│ 4. Modern design                                                    │
│    - Clean 64-bit architecture from the start                      │
│    - No legacy 16-bit/32-bit baggage                              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Sub-lesson 1.4: Assembly Syntax

### The Problem

What assembly syntax does ARM64 use? Is it like x86 AT&T or Intel syntax?

### The Solution

ARM64 uses its own syntax (similar to Intel style in some ways):

```asm
// ARM64 syntax
mov     w0, #42         // w0 = 42
add     w2, w0, w1      // w2 = w0 + w1
ret                     // return
```

Compare to x86 AT&T:
```asm
# x86 AT&T syntax
movl    $42, %eax       # eax = 42
addl    %ecx, %eax      # eax = eax + ecx
ret                     # return
```

**ARM64 Syntax Rules:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ ARM64 SYNTAX RULES                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Format: opcode  dst, src1, src2    (3 operands for most ops)       │
│         opcode  dst, src           (2 operands for mov, etc.)      │
│                                                                     │
│ Registers:                                                          │
│   x0-x30  = 64-bit registers                                       │
│   w0-w30  = 32-bit (lower half of x registers)                     │
│   sp      = stack pointer                                          │
│   No % prefix (unlike x86 AT&T)                                    │
│                                                                     │
│ Immediates:                                                         │
│   #42     = immediate value (use # prefix)                         │
│   #-1     = negative immediate                                     │
│                                                                     │
│ Comments:                                                           │
│   // comment   or   /* comment */                                  │
│                                                                     │
│ Examples:                                                           │
│   mov   w0, #42        // w0 = 42                                  │
│   add   w2, w0, w1     // w2 = w0 + w1                            │
│   sub   w0, w0, #1     // w0 = w0 - 1                             │
│   mul   w3, w1, w2     // w3 = w1 * w2                            │
│   sdiv  w4, w0, w1     // w4 = w0 / w1 (signed)                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Differences from x86:**

| Feature | ARM64 | x86 AT&T |
|---------|-------|----------|
| Operand order | `dst, src` | `src, dst` |
| Register prefix | None (`w0`) | `%` (`%eax`) |
| Immediate prefix | `#` (`#42`) | `$` (`$42`) |
| Arithmetic | 3-operand (`add w2, w0, w1`) | 2-operand (`addl %ecx, %eax`) |
| Comments | `//` or `/* */` | `#` |

---

## Summary: Our ARM64 Backend Design

```
┌────────────────────────────────────────────────────────────────────┐
│ ARM64 BACKEND DESIGN DECISIONS                                     │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ Target:       ARM64/AArch64 (64-bit ARM)                          │
│ Platforms:    macOS (Apple Silicon), Linux ARM64                  │
│ Syntax:       ARM assembly (dst, src1, src2)                      │
│ Assembler:    GNU as or Apple clang                               │
│ Output:       .s text file → assembled with `as`                  │
│                                                                    │
│ What we generate:                                                  │
│   - Assembly text (human-readable)                                │
│   - No optimizations (clarity over speed)                         │
│   - AAPCS64 calling convention                                    │
│                                                                    │
│ Build command:                                                     │
│   cc -o program output.s                                          │
│                                                                    │
│ macOS note:                                                        │
│   Functions need underscore prefix: _main, _add                   │
│   Linux uses: main, add (no underscore)                           │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Verify your ARM64 system is ready:

```bash
# Check architecture
uname -m
# Should print: arm64 or aarch64

# Write a minimal assembly file (macOS)
cat > test.s << 'EOF'
    .text
    .globl _main
_main:
    mov     w0, #42
    ret
EOF

# Assemble and link
cc -o test test.s

# Run (should exit with code 42)
./test
echo $?
```

**For Linux ARM64**, remove the underscore:
```bash
cat > test.s << 'EOF'
    .text
    .globl main
main:
    mov     w0, #42
    ret
EOF

cc -o test test.s
./test
echo $?
```

If you see `42`, you're ready for the next lesson!

---

## What's Next

Now that we understand why ARM64 is valuable, let's learn its architecture: registers, instructions, and how they work.

**Next: [Lesson 2: ARM64 Basics](../02-arm64-basics/)** →
