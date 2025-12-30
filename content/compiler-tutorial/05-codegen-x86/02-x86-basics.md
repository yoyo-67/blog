---
title: "Lesson 2: x86-64 Basics"
weight: 2
---

# Lesson 2: x86-64 Basics

Before generating code, you need to understand the target machine. This lesson teaches you the essential x86-64 concepts: registers, instructions, and addressing modes.

**What you'll learn:**
- The 16 general-purpose registers and their sizes
- How x86 instructions work
- Memory addressing modes
- The instructions we'll use for code generation

---

## Sub-lesson 2.1: General-Purpose Registers

### The Problem

The CPU needs places to store data while computing. These are **registers**: tiny, ultra-fast storage locations inside the CPU.

How many do we have? Which ones can we use? Do they have special purposes?

### The Solution

x86-64 has **16 general-purpose registers**. Each is 64 bits wide.

```
┌─────────────────────────────────────────────────────────────────────┐
│ x86-64 GENERAL-PURPOSE REGISTERS                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Classic registers (from 8086, extended to 64 bits):                 │
│   rax  rbx  rcx  rdx  rsi  rdi  rbp  rsp                           │
│                                                                     │
│ New registers (added in x86-64):                                    │
│   r8   r9   r10  r11  r12  r13  r14  r15                           │
│                                                                     │
│ Total: 16 registers                                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Some have special roles:**

| Register | Special Purpose |
|----------|-----------------|
| `rsp` | Stack pointer (points to top of stack) |
| `rbp` | Base pointer (points to current stack frame) |
| `rax` | Return value from functions |
| `rdi, rsi, rdx, rcx, r8, r9` | Function arguments (in order) |

**The rest** (`rbx`, `r10`-`r15`) are general-purpose "scratch" registers we can use freely (with some caveats we'll cover later).

---

## Sub-lesson 2.2: Register Sizes

### The Problem

Our language uses `i32` (32-bit integers), but the registers are 64 bits wide. How do we work with 32-bit values?

### The Solution

Each 64-bit register has smaller "views" that access subsets of its bits:

```
┌─────────────────────────────────────────────────────────────────────┐
│ REGISTER SIZE VIEWS (using rax as example)                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ 64 bits: rax   ████████████████████████████████████████████████    │
│                 │                                           │       │
│ 32 bits: eax   │                   ████████████████████████ │       │
│                 │                   │                     │ │       │
│ 16 bits: ax    │                   │         ████████████ │ │       │
│                 │                   │         │         │ │ │       │
│  8 bits: al    │                   │         │    ████ │ │ │       │
│                 │                   │         │         │ │ │       │
│          ah    │                   │         │████     │ │ │       │
│                 │                   │                     │ │       │
│                 bits 63-32          bits 31-0             │ │       │
│                                                           │ │       │
└─────────────────────────────────────────────────────────────────────┘
```

**Register naming pattern:**

| Size | Classic Registers | New Registers |
|------|------------------|---------------|
| 64-bit | rax, rbx, rcx, rdx, rsi, rdi, rbp, rsp | r8, r9, r10, ... r15 |
| 32-bit | eax, ebx, ecx, edx, esi, edi, ebp, esp | r8d, r9d, r10d, ... r15d |
| 16-bit | ax, bx, cx, dx, si, di, bp, sp | r8w, r9w, r10w, ... r15w |
| 8-bit | al, bl, cl, dl, sil, dil, bpl, spl | r8b, r9b, r10b, ... r15b |

**For our i32 type, we'll use the 32-bit names:**
- `%eax` instead of `%rax`
- `%edi` instead of `%rdi`
- `%r10d` instead of `%r10`

**Important x86-64 rule**: Writing to a 32-bit register (like `eax`) automatically **zeros the upper 32 bits** of the 64-bit register (`rax`). This is helpful and avoids surprises.

---

## Sub-lesson 2.3: Instruction Format

### The Problem

How do x86 instructions work? What's the structure of an assembly line?

### The Solution

AT&T syntax follows this pattern:

```
opcode{suffix}    source, destination
```

**Components:**

| Part | Meaning | Example |
|------|---------|---------|
| opcode | The operation | `mov`, `add`, `sub` |
| suffix | Size (b/w/l/q) | `l` for 32-bit |
| source | Where data comes from | `%esi`, `$42` |
| destination | Where data goes | `%eax` |

**Common instructions we'll use:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ ESSENTIAL x86 INSTRUCTIONS                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Data Movement:                                                      │
│   movl  src, dst       # dst = src                                 │
│                                                                     │
│ Arithmetic:                                                         │
│   addl  src, dst       # dst = dst + src                           │
│   subl  src, dst       # dst = dst - src                           │
│   imull src, dst       # dst = dst * src (signed)                  │
│   idivl src            # eax = edx:eax / src (special!)            │
│   negl  dst            # dst = -dst                                │
│                                                                     │
│ Stack Operations:                                                   │
│   pushq reg            # push 64-bit register onto stack           │
│   popq  reg            # pop from stack into register              │
│                                                                     │
│ Control Flow:                                                       │
│   call  label          # call function                             │
│   ret                  # return from function                      │
│   jmp   label          # unconditional jump                        │
│                                                                     │
│ Comparison:                                                         │
│   cmpl  src, dst       # compare (sets flags)                      │
│   je    label          # jump if equal                             │
│   jne   label          # jump if not equal                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Examples:**

```asm
movl    $42, %eax       # eax = 42 (immediate to register)
movl    %esi, %eax      # eax = esi (register to register)
addl    %ebx, %eax      # eax = eax + ebx
subl    $1, %ecx        # ecx = ecx - 1
imull   %edx, %eax      # eax = eax * edx
```

---

## Sub-lesson 2.4: Operand Types

### The Problem

Instructions take operands, but there are different kinds: constants, registers, memory locations. How do we specify each?

### The Solution

There are three main operand types:

**1. Immediate (constant values)**
```asm
movl    $42, %eax       # $ prefix indicates immediate
movl    $-1, %ebx       # negative numbers work too
movl    $0, %ecx        # zero
```

**2. Register**
```asm
movl    %esi, %eax      # % prefix indicates register
addl    %ebx, %eax      # both operands are registers
```

**3. Memory (we won't use this much)**
```asm
movl    (%rsp), %eax    # load from address in rsp
movl    8(%rbp), %eax   # load from rbp+8 (stack variable)
movl    %eax, -4(%rbp)  # store to rbp-4
```

**For our simple compiler, we'll mostly use immediates and registers.** Memory access is mainly for stack spills (when we run out of registers).

```
┌─────────────────────────────────────────────────────────────────────┐
│ OPERAND TYPE SUMMARY                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Type       Syntax          Example         Meaning                  │
│ ─────────  ──────────────  ──────────────  ───────────────────────  │
│ Immediate  $number         $42             constant value 42        │
│ Register   %reg            %eax            contents of eax          │
│ Memory     offset(%reg)    8(%rbp)         memory at rbp+8          │
│ Direct     label           my_var          address of my_var        │
│                                                                     │
│ Valid combinations for movl:                                        │
│   movl $imm, %reg     ✓    (constant → register)                   │
│   movl %reg, %reg     ✓    (register → register)                   │
│   movl %reg, mem      ✓    (register → memory)                     │
│   movl mem, %reg      ✓    (memory → register)                     │
│   movl $imm, mem      ✓    (constant → memory)                     │
│   movl mem, mem       ✗    (memory → memory NOT allowed!)          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Summary: x86-64 Quick Reference

```
┌────────────────────────────────────────────────────────────────────┐
│ x86-64 QUICK REFERENCE                                             │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ 16 General-Purpose Registers:                                      │
│   rax rbx rcx rdx rsi rdi rbp rsp r8 r9 r10 r11 r12 r13 r14 r15   │
│                                                                    │
│ 32-bit versions (for i32):                                         │
│   eax ebx ecx edx esi edi ebp esp r8d r9d r10d r11d r12d-r15d     │
│                                                                    │
│ AT&T Syntax:                                                       │
│   opcode{size}  source, destination                                │
│   movl  $42, %eax      # eax = 42                                 │
│   addl  %esi, %eax     # eax += esi                               │
│                                                                    │
│ Size suffixes:                                                     │
│   b = byte (8)   w = word (16)   l = long (32)   q = quad (64)    │
│                                                                    │
│ Prefixes:                                                          │
│   $ = immediate value                                              │
│   % = register                                                     │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Write a simple assembly program that computes `10 + 32`:

```bash
cat > compute.s << 'EOF'
    .text
    .globl main
main:
    movl    $10, %eax       # eax = 10
    addl    $32, %eax       # eax = eax + 32 = 42
    ret                      # return eax as exit code
EOF

cc -o compute compute.s
./compute
echo $?  # Should print 42
```

Now try subtraction and multiplication:

```bash
cat > ops.s << 'EOF'
    .text
    .globl main
main:
    movl    $50, %eax       # eax = 50
    subl    $8, %eax        # eax = 42
    ret
EOF

cc -o ops ops.s && ./ops && echo $?  # Should print 42
```

---

## What's Next

We know the registers and instructions. But how do functions receive parameters and return values? That's determined by the **calling convention**.

**Next: [Lesson 3: Calling Convention](../03-calling-convention/)** →
