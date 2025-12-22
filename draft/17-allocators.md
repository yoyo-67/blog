---
title: "Part 17: Allocators Deep Dive - Inside Zig's Memory Management"
date: 2025-12-21
---

# Part 17: Allocators Deep Dive - Inside Zig's Memory Management

In Part 12, we introduced Zig's allocator system. Now we'll go deeper - examining the actual implementation of each allocator, understanding their internal data structures, and learning when each one shines.

But first, let's understand how memory actually works - from the hardware up.

---

## Part 0: How Memory Really Works

Before we can understand allocators, we need to understand what they're actually managing.

### Physical Memory: The Hardware Reality

Your computer has RAM - physical chips that store bytes. Each byte has an address:

```
┌─────────────────────────────────────────────────────────────┐
│                    PHYSICAL RAM (8GB example)                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Address        Content                                      │
│  ────────       ───────                                      │
│  0x00000000     [byte] [byte] [byte] [byte] ...             │
│  0x00000004     [byte] [byte] [byte] [byte] ...             │
│  0x00000008     [byte] [byte] [byte] [byte] ...             │
│  ...                                                         │
│  0x1FFFFFFFF    [byte] [byte] [byte] [byte]  ← Last byte    │
│                                               (8GB = 2^33)  │
│                                                              │
│  Physical RAM is just a giant array of bytes!               │
│  RAM[address] = byte_value                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**The CPU reads/writes memory through the memory bus:**

```
┌─────────────┐                      ┌─────────────────────┐
│     CPU     │ ◄─── Memory Bus ───► │        RAM          │
│             │                      │                     │
│  "Read from │   Address: 0x1000    │  Returns: 0x42      │
│   0x1000"   │   ─────────────────► │                     │
│             │   ◄───────────────── │                     │
│             │   Data: 0x42         │                     │
└─────────────┘                      └─────────────────────┘
```

### The Problem: Multiple Programs

What happens when you run multiple programs?

```
┌─────────────────────────────────────────────────────────────┐
│                    THE PROBLEM                               │
│                                                              │
│  Program A thinks it owns address 0x1000                    │
│  Program B thinks it owns address 0x1000                    │
│                                                              │
│  Both compiled to use the same addresses!                   │
│                                                              │
│  ┌─────────────┐    ┌─────────────┐                         │
│  │  Program A  │    │  Program B  │                         │
│  │             │    │             │                         │
│  │ ptr = 0x1000│    │ ptr = 0x1000│                         │
│  │ *ptr = 42   │    │ *ptr = 99   │  ← They'd overwrite    │
│  └─────────────┘    └─────────────┘    each other!         │
│                                                              │
│  Also: What if Program A tries to read Program B's          │
│  passwords stored in memory? SECURITY DISASTER!             │
└─────────────────────────────────────────────────────────────┘
```

### The Solution: Virtual Memory

Every process gets its own **virtual address space** - an illusion that it has all memory to itself:

```
┌─────────────────────────────────────────────────────────────┐
│                    VIRTUAL MEMORY                            │
│                                                              │
│  Program A's View:           Program B's View:              │
│  ┌─────────────────┐        ┌─────────────────┐             │
│  │ 0x0000 - 0xFFFF │        │ 0x0000 - 0xFFFF │             │
│  │ (all mine!)     │        │ (all mine!)     │             │
│  │                 │        │                 │             │
│  │ 0x1000: my data │        │ 0x1000: my data │             │
│  └────────┬────────┘        └────────┬────────┘             │
│           │                          │                       │
│           │ TRANSLATION              │ TRANSLATION           │
│           ▼                          ▼                       │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                   PHYSICAL RAM                       │    │
│  │                                                      │    │
│  │  A's 0x1000 ──► Physical 0x50000                    │    │
│  │  B's 0x1000 ──► Physical 0x80000                    │    │
│  │                                                      │    │
│  │  Different physical locations!                       │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  The OS + CPU translate virtual → physical addresses        │
│  Programs never see real physical addresses                  │
└─────────────────────────────────────────────────────────────┘
```

### Pages: The Unit of Memory Management

Memory isn't managed byte-by-byte - that would require a translation table entry for every single byte! Instead, memory is divided into **pages**:

```
┌─────────────────────────────────────────────────────────────┐
│                    MEMORY PAGES                              │
│                                                              │
│  Typical page size: 4KB (4096 bytes)                        │
│  Some systems: 16KB, 64KB, or "huge pages" of 2MB/1GB       │
│                                                              │
│  Virtual Address Space (divided into pages):                │
│  ┌────────┬────────┬────────┬────────┬────────┬────────┐   │
│  │ Page 0 │ Page 1 │ Page 2 │ Page 3 │ Page 4 │  ...   │   │
│  │ 0-4095 │4096-   │8192-   │12288-  │16384-  │        │   │
│  │        │8191    │12287   │16383   │20479   │        │   │
│  └────────┴────────┴────────┴────────┴────────┴────────┘   │
│                                                              │
│  Physical RAM (also divided into pages, called "frames"):   │
│  ┌────────┬────────┬────────┬────────┬────────┬────────┐   │
│  │Frame 0 │Frame 1 │Frame 2 │Frame 3 │Frame 4 │  ...   │   │
│  └────────┴────────┴────────┴────────┴────────┴────────┘   │
│                                                              │
│  Each virtual page maps to a physical frame                  │
│  (or to nothing - "not present")                             │
└─────────────────────────────────────────────────────────────┘
```

### The Page Table: Where Translation Happens

Every process has a **page table** - a data structure mapping virtual pages to physical frames:

```
┌─────────────────────────────────────────────────────────────┐
│                   PAGE TABLE (per process)                   │
│                                                              │
│  Virtual Page    Physical Frame    Flags                    │
│  ────────────    ──────────────    ─────                    │
│  Page 0     ──►  Frame 47          [R, W, Present]          │
│  Page 1     ──►  Frame 123         [R, Present]             │
│  Page 2     ──►  (not present)     [Not Present]            │
│  Page 3     ──►  Frame 8           [R, W, X, Present]       │
│  Page 4     ──►  (not present)     [Not Present]            │
│  ...                                                         │
│                                                              │
│  Flags:                                                      │
│    R = Readable                                              │
│    W = Writable                                              │
│    X = Executable                                            │
│    Present = Actually in physical RAM                        │
│                                                              │
│  The page table lives in RAM, managed by the OS             │
└─────────────────────────────────────────────────────────────┘
```

### The MMU: Hardware That Does Translation

The CPU has a special unit called the **MMU (Memory Management Unit)** that translates addresses on every memory access:

```
┌─────────────────────────────────────────────────────────────┐
│                 ADDRESS TRANSLATION (MMU)                    │
│                                                              │
│  Your code: ptr = 0x00003042                                │
│                    ▼                                         │
│  ┌─────────────────────────────────────────────────┐        │
│  │ Virtual Address: 0x00003042                      │        │
│  │                                                  │        │
│  │ Split into:                                      │        │
│  │   Page Number: 0x00003  (which page?)           │        │
│  │   Offset:      0x042    (where in that page?)   │        │
│  └─────────────────────────────────────────────────┘        │
│                    ▼                                         │
│  ┌─────────────────────────────────────────────────┐        │
│  │ MMU looks up Page 3 in Page Table               │        │
│  │                                                  │        │
│  │ Page 3 ──► Frame 8                              │        │
│  └─────────────────────────────────────────────────┘        │
│                    ▼                                         │
│  ┌─────────────────────────────────────────────────┐        │
│  │ Physical Address = Frame 8 base + Offset        │        │
│  │                  = 0x00008000 + 0x042           │        │
│  │                  = 0x00008042                   │        │
│  └─────────────────────────────────────────────────┘        │
│                    ▼                                         │
│  RAM access at physical address 0x00008042                  │
│                                                              │
│  This happens FOR EVERY memory access!                      │
│  (But it's fast - the MMU is in hardware + TLB cache)       │
└─────────────────────────────────────────────────────────────┘
```

### Page Faults: When Things Aren't Present

What happens when you access a page that's "not present"?

```
┌─────────────────────────────────────────────────────────────┐
│                      PAGE FAULT                              │
│                                                              │
│  1. Your code accesses address 0x5000                       │
│  2. MMU looks up page 5 in page table                       │
│  3. Page 5 says "NOT PRESENT"                               │
│  4. MMU triggers a PAGE FAULT (CPU exception)               │
│  5. OS kernel takes over                                    │
│                                                              │
│  The OS then decides what to do:                            │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Case A: Valid access, page just not loaded yet       │   │
│  │         (e.g., lazy allocation, swapped to disk)     │   │
│  │                                                      │   │
│  │   → OS allocates physical frame                      │   │
│  │   → OS updates page table: Page 5 → Frame N         │   │
│  │   → OS resumes your program (retry the access)       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Case B: Invalid access (you accessed bad memory!)    │   │
│  │                                                      │   │
│  │   → OS sends SIGSEGV signal                          │   │
│  │   → Your program crashes: "Segmentation fault"       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  This is how:                                               │
│  • NULL pointer access is caught (page 0 marked invalid)   │
│  • Programs can't access each other's memory               │
│  • Lazy memory allocation works                             │
└─────────────────────────────────────────────────────────────┘
```

### How Programs Get Memory: mmap and brk

When your program needs memory, it asks the OS using **system calls**:

```
┌─────────────────────────────────────────────────────────────┐
│               GETTING MEMORY FROM THE OS                     │
│                                                              │
│  Two main syscalls on Linux:                                │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                      mmap()                          │   │
│  │                                                      │   │
│  │  "Give me N bytes of virtual address space"          │   │
│  │                                                      │   │
│  │  1. OS finds unused region in your virtual space     │   │
│  │  2. OS creates page table entries (marked not-present│   │
│  │     initially - lazy allocation!)                    │   │
│  │  3. Returns pointer to start of region               │   │
│  │                                                      │   │
│  │  void* ptr = mmap(NULL, 4096,                       │   │
│  │                   PROT_READ | PROT_WRITE,           │   │
│  │                   MAP_PRIVATE | MAP_ANONYMOUS,       │   │
│  │                   -1, 0);                           │   │
│  │                                                      │   │
│  │  PROT_READ  = pages will be readable                │   │
│  │  PROT_WRITE = pages will be writable                │   │
│  │  MAP_PRIVATE = changes are private to this process  │   │
│  │  MAP_ANONYMOUS = not backed by a file               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                      munmap()                        │   │
│  │                                                      │   │
│  │  "I'm done with this memory region"                  │   │
│  │                                                      │   │
│  │  munmap(ptr, 4096);                                 │   │
│  │                                                      │   │
│  │  • OS marks those pages as invalid                   │   │
│  │  • Physical frames returned to system                │   │
│  │  • Future accesses = segfault                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  This is exactly what Zig's PageAllocator does!             │
└─────────────────────────────────────────────────────────────┘
```

### Lazy Allocation: Memory That Doesn't Exist Yet

Here's a surprising fact - when you mmap memory, it doesn't immediately use RAM:

```
┌─────────────────────────────────────────────────────────────┐
│                   LAZY ALLOCATION                            │
│                                                              │
│  Step 1: mmap(NULL, 1GB, ...)                               │
│                                                              │
│  Page Table:                                                │
│  ┌──────────────────────────────────────────────────┐      │
│  │ Page 0: [Not Present, but VALID when accessed]    │      │
│  │ Page 1: [Not Present, but VALID when accessed]    │      │
│  │ Page 2: [Not Present, but VALID when accessed]    │      │
│  │ ... 262,000+ pages ...                            │      │
│  └──────────────────────────────────────────────────┘      │
│                                                              │
│  Physical RAM used: ~0 bytes!                               │
│  Virtual space reserved: 1GB                                │
│                                                              │
│  Step 2: You write to address in Page 0                     │
│                                                              │
│  ┌──────────────────────────────────────────────────┐      │
│  │ 1. MMU sees "Not Present" → PAGE FAULT            │      │
│  │ 2. OS sees "this is a valid mmap'd region"        │      │
│  │ 3. OS allocates ONE physical frame (4KB)          │      │
│  │ 4. OS updates page table: Page 0 → Frame N        │      │
│  │ 5. OS resumes your code                           │      │
│  └──────────────────────────────────────────────────┘      │
│                                                              │
│  Physical RAM used: 4KB                                     │
│  Only pages you ACTUALLY TOUCH use real RAM!                │
│                                                              │
│  This is why you can mmap huge regions cheaply.             │
│  It's also why memory usage grows as you access memory.     │
└─────────────────────────────────────────────────────────────┘
```

### Memory Layout of a Process

Every process has a standard memory layout:

```
┌─────────────────────────────────────────────────────────────┐
│            VIRTUAL ADDRESS SPACE LAYOUT                      │
│                                                              │
│  High addresses (e.g., 0x7FFFFFFFFFFF on 64-bit Linux)      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                      STACK                            │   │
│  │  • Local variables                                    │   │
│  │  • Function call frames                               │   │
│  │  • Grows DOWNWARD ↓                                   │   │
│  │                                                       │   │
│  │  var x: u32 = 42;  // lives here                     │   │
│  │                         ↓                             │   │
│  ├───────────────────────────────────────────────────────┤   │
│  │                    (unmapped gap)                     │   │
│  │              Stack overflow = segfault                │   │
│  ├───────────────────────────────────────────────────────┤   │
│  │                                                       │   │
│  │                   MEMORY MAPPINGS                     │   │
│  │  • mmap() allocations                                 │   │
│  │  • Shared libraries (.so files)                       │   │
│  │  • Grows downward (usually)                           │   │
│  │                                                       │   │
│  ├───────────────────────────────────────────────────────┤   │
│  │                    (unmapped gap)                     │   │
│  ├───────────────────────────────────────────────────────┤   │
│  │                         ↑                             │   │
│  │                       HEAP                            │   │
│  │  • malloc/allocator memory                            │   │
│  │  • Grows UPWARD ↑                                     │   │
│  │                                                       │   │
│  │  var ptr = allocator.alloc(...);  // lives here      │   │
│  ├───────────────────────────────────────────────────────┤   │
│  │                       BSS                             │   │
│  │  • Uninitialized global variables                     │   │
│  │  • var global: [1000]u8 = undefined;                 │   │
│  ├───────────────────────────────────────────────────────┤   │
│  │                       DATA                            │   │
│  │  • Initialized global variables                       │   │
│  │  • const message = "hello";                          │   │
│  ├───────────────────────────────────────────────────────┤   │
│  │                       TEXT                            │   │
│  │  • Your compiled code (machine instructions)          │   │
│  │  • Read-only + Executable                             │   │
│  ├───────────────────────────────────────────────────────┤   │
│  │  0x0 - typically unmapped (NULL pointer protection)  │   │
│  └──────────────────────────────────────────────────────┘   │
│  Low addresses (0x0)                                        │
└─────────────────────────────────────────────────────────────┘
```

### Stack vs Heap: Two Ways to Allocate

```
┌─────────────────────────────────────────────────────────────┐
│                    STACK ALLOCATION                          │
│                                                              │
│  fn example() void {                                        │
│      var buffer: [1024]u8 = undefined;  // ON STACK         │
│      var x: u32 = 42;                   // ON STACK         │
│  }  // Everything freed automatically when function returns │
│                                                              │
│  How it works:                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Stack pointer (SP) register = 0x7FFE0000           │    │
│  │                                                     │    │
│  │ Before call:  SP ──► [previous frame data]         │    │
│  │                                                     │    │
│  │ Enter func:   SP -= 1028  (make room)              │    │
│  │               SP ──► [buffer: 1024 bytes]          │    │
│  │                      [x: 4 bytes]                  │    │
│  │                      [previous frame data]         │    │
│  │                                                     │    │
│  │ Return:       SP += 1028  (restore)                │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  • FAST: Just move stack pointer (single instruction)       │
│  • AUTOMATIC: Freed when function returns                   │
│  • LIMITED: Stack size is fixed (usually 1-8 MB)           │
│  • LIFO: Can't free in arbitrary order                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    HEAP ALLOCATION                           │
│                                                              │
│  fn example(allocator: Allocator) !void {                   │
│      var buffer = try allocator.alloc(u8, 1024);  // HEAP   │
│      defer allocator.free(buffer);                          │
│  }                                                          │
│                                                              │
│  How it works:                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Allocator maintains data structures tracking:       │    │
│  │   • Which regions are free                          │    │
│  │   • Which regions are in use                        │    │
│  │   • Size of each allocation                         │    │
│  │                                                     │    │
│  │ alloc(): Find free region, mark as used, return ptr │    │
│  │ free():  Mark region as free for reuse             │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  • FLEXIBLE: Allocate any size, free in any order          │
│  • UNLIMITED: Can grow (via mmap) as needed                │
│  • SLOWER: Bookkeeping overhead                             │
│  • MANUAL: Must free explicitly (or use defer)             │
└─────────────────────────────────────────────────────────────┘
```

### Memory Alignment: Why It Matters

CPUs work most efficiently when data is "aligned" to certain boundaries:

```
┌─────────────────────────────────────────────────────────────┐
│                   MEMORY ALIGNMENT                           │
│                                                              │
│  CPU reads memory in "words" (4 or 8 bytes at a time)       │
│                                                              │
│  Aligned u32 at address 0x1000:                             │
│  ┌────┬────┬────┬────┬────┬────┬────┬────┐                 │
│  │ 0  │ 1  │ 2  │ 3  │ 4  │ 5  │ 6  │ 7  │  address       │
│  ├────┴────┴────┴────┼────┴────┴────┴────┤                 │
│  │    your u32       │    next word       │                 │
│  └───────────────────┴───────────────────┘                 │
│  ◄─── one read ─────►                                       │
│  CPU reads bytes 0-3 in ONE memory access. FAST!           │
│                                                              │
│  Misaligned u32 at address 0x1002:                          │
│  ┌────┬────┬────┬────┬────┬────┬────┬────┐                 │
│  │ 0  │ 1  │ 2  │ 3  │ 4  │ 5  │ 6  │ 7  │  address       │
│  ├────┴────┼────┴────┴────┴────┼────┴────┤                 │
│  │  ??     │    your u32       │   ??    │                 │
│  └─────────┴───────────────────┴─────────┘                 │
│  ◄─ read 1 ─►◄──── read 2 ────►                            │
│  CPU needs TWO memory accesses + shifting. SLOW!           │
│  (Some CPUs will fault/crash on misaligned access)         │
│                                                              │
│  Alignment rules:                                           │
│    u8  - any address (1-byte aligned)                       │
│    u16 - even addresses (2-byte aligned)                    │
│    u32 - addresses divisible by 4 (4-byte aligned)          │
│    u64 - addresses divisible by 8 (8-byte aligned)          │
│    SIMD - often 16-byte or 32-byte aligned                  │
└─────────────────────────────────────────────────────────────┘
```

This is why Zig allocators take an `alignment` parameter!

```zig
// You specify what alignment you need
const ptr = allocator.alignedAlloc(u8, .@"16", 100);
// Returns address divisible by 16
```

### The Cost of Syscalls

Asking the OS for memory (mmap) is expensive:

```
┌─────────────────────────────────────────────────────────────┐
│                   SYSCALL OVERHEAD                           │
│                                                              │
│  Normal function call: ~1-5 CPU cycles                      │
│  System call: ~100-1000+ CPU cycles                         │
│                                                              │
│  What happens during a syscall:                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │ 1. Save all CPU registers                           │    │
│  │ 2. Switch from user mode to kernel mode             │    │
│  │ 3. Look up syscall handler                          │    │
│  │ 4. Execute kernel code                              │    │
│  │ 5. Switch back to user mode                         │    │
│  │ 6. Restore all CPU registers                        │    │
│  │ 7. Resume your program                              │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  This is why allocators exist!                              │
│                                                              │
│  Bad:  Every allocation = mmap() syscall                    │
│  Good: mmap() big chunks, subdivide them ourselves          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │           What allocators do:                       │    │
│  │                                                     │    │
│  │   mmap(64KB) ─► [                                  ]│    │
│  │                                                     │    │
│  │   alloc(100) ─► [████     ]  (no syscall!)         │    │
│  │   alloc(200) ─► [████████ ]  (no syscall!)         │    │
│  │   alloc(50)  ─► [██████████] (no syscall!)         │    │
│  │                                                     │    │
│  │   One syscall serves many allocations!              │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Putting It All Together

Now you understand why Zig's allocators work the way they do:

```
┌─────────────────────────────────────────────────────────────┐
│             HOW ALLOCATORS FIT INTO THE PICTURE              │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    YOUR CODE                         │   │
│  │  var data = try allocator.alloc(u8, 100);           │   │
│  └─────────────────────────┬───────────────────────────┘   │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              ALLOCATOR (Arena, GPA, etc.)            │   │
│  │                                                      │   │
│  │  • Manages chunks of memory                          │   │
│  │  • Subdivides into smaller pieces                    │   │
│  │  • Tracks what's free/used                          │   │
│  │  • Handles alignment                                 │   │
│  └─────────────────────────┬───────────────────────────┘   │
│                            ▼ (occasionally)                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   PageAllocator                      │   │
│  │                                                      │   │
│  │  mmap() / munmap() syscalls                         │   │
│  └─────────────────────────┬───────────────────────────┘   │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   OPERATING SYSTEM                   │   │
│  │                                                      │   │
│  │  • Updates page tables                               │   │
│  │  • Allocates physical frames (lazily)               │   │
│  │  • Manages virtual address space                     │   │
│  └─────────────────────────┬───────────────────────────┘   │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                      MMU + RAM                       │   │
│  │                                                      │   │
│  │  • Translates virtual → physical                     │   │
│  │  • Actual bytes in silicon                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  Each layer adds abstraction:                               │
│  Physical RAM → Virtual Memory → Pages → Allocator → You   │
└─────────────────────────────────────────────────────────────┘
```

---

## The Allocator Interface

Before diving into specific allocators, let's understand what they all have in common.

Every allocator in Zig is just two pointers bundled together:

```
┌─────────────────────────────────────────────────────────┐
│                    Allocator (16 bytes)                  │
├─────────────────────────────────────────────────────────┤
│  ptr: *anyopaque     ──────► [Allocator's internal      │
│                               state/data]               │
│                                                          │
│  vtable: *VTable     ──────► ┌─────────────────────┐    │
│                               │ alloc:  fn pointer │    │
│                               │ resize: fn pointer │    │
│                               │ remap:  fn pointer │    │
│                               │ free:   fn pointer │    │
│                               └─────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

**Why this design?**
- Any allocator can be passed to any function expecting `Allocator`
- No generics needed at the call site
- The caller doesn't need to know which allocator implementation is used
- Cost: one pointer indirection per call (usually negligible)

---

## 1. PageAllocator - The Foundation

**Source:** `std/heap/PageAllocator.zig` (199 lines)
**Access:** `std.heap.page_allocator`

### The Simple Idea

PageAllocator is the simplest possible allocator - it just asks the operating system for memory directly. Every allocation is a syscall.

```
┌─────────────────────────────────────────────────────────┐
│                   YOUR PROGRAM                           │
│                                                          │
│   const ptr = page_allocator.alloc(u8, 1000);           │
│                         │                                │
│                         ▼                                │
│              ┌─────────────────────┐                    │
│              │   PageAllocator     │                    │
│              │   (no state!)       │                    │
│              └──────────┬──────────┘                    │
│                         │                                │
│                         ▼ mmap() syscall                 │
├─────────────────────────────────────────────────────────┤
│                 OPERATING SYSTEM                         │
│                                                          │
│   "Here's 4096 bytes (one page) of memory"              │
│   (You asked for 1000, but I only deal in pages)        │
└─────────────────────────────────────────────────────────┘
```

### What Happens When You Allocate

Let's trace through `page_allocator.alloc(u8, 100)`:

```
Step 1: You ask for 100 bytes
        ↓
Step 2: PageAllocator calls mmap(NULL, 4096, PROT_READ|PROT_WRITE, ...)
        (4096 = page size, the minimum the OS will give)
        ↓
Step 3: OS returns pointer to a fresh 4096-byte region
        ↓
Step 4: You get back that pointer

Memory layout:
┌────────────────────────────────────────────────────────────┐
│ Address 0x7f4a00000000                                      │
├────────────────────────────────────────────────────────────┤
│ ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ◄──100 bytes─►◄────────── 3996 bytes wasted ──────────────►│
│   (your data)                (padding to page size)         │
└────────────────────────────────────────────────────────────┘
```

### Alignment Handling - The Clever Trick

What if you need 64KB alignment but the OS gives you an unaligned address?

```
You want: 64KB-aligned memory (address must be multiple of 65536)
OS gives: 0x7f4a00001000 (not aligned to 64KB)

PageAllocator's solution: Over-allocate, then trim!

Step 1: Ask for MORE than needed
        Request size + alignment = extra room to find aligned spot

Step 2: OS returns unaligned region:
        ┌──────────────────────────────────────────────────────┐
        │░░░░░░░░░░░░░░░░████████████████████████░░░░░░░░░░░░░░│
        ▲               ▲                       ▲              ▲
        │               │                       │              │
     OS start     Aligned spot            Your data ends    OS end
    (unaligned)   (we'll use this)

Step 3: Unmap the unusable parts:
        - munmap(OS start, prefix_length)
        - munmap(suffix_start, suffix_length)

Step 4: Return the aligned middle section
```

The actual code:
```zig
// Unmap prefix (bytes before aligned address)
const drop_len = result_ptr - slice.ptr;
if (drop_len != 0) posix.munmap(slice[0..drop_len]);

// Unmap suffix (extra bytes at end)
if (remaining_len > aligned_len)
    posix.munmap(@alignCast(result_ptr[aligned_len..remaining_len]));
```

### When to Use PageAllocator

```
┌─────────────────────────────────────────────────────────┐
│ Good for:                    │ Bad for:                 │
├──────────────────────────────┼──────────────────────────┤
│ ✓ Backing other allocators   │ ✗ Small allocations      │
│ ✓ Large, long-lived data     │ ✗ Frequent alloc/free    │
│ ✓ Thread safety (free!)      │ ✗ Memory efficiency      │
│ ✓ Simplicity                 │ ✗ Performance-critical   │
└──────────────────────────────┴──────────────────────────┘

Overhead: ~4KB minimum per allocation (one page)
Speed: Slow (syscall per operation)
```

---

## 2. ArenaAllocator - The Batch Processor

**Source:** `std/heap/arena_allocator.zig` (307 lines)
**Access:** `std.heap.ArenaAllocator`

### The Simple Idea

Arena is a "bump allocator" - allocations just bump a pointer forward. You can't free individual items, but you can free EVERYTHING at once.

Think of it like a notepad: you write, write, write... then tear off all the pages at once.

```
┌─────────────────────────────────────────────────────────┐
│                   ARENA CONCEPT                          │
│                                                          │
│  Traditional allocator:        Arena allocator:          │
│  ┌───┬───┬───┬───┬───┐        ┌───────────────────────┐ │
│  │ A │ B │ C │ D │ E │        │ A B C D E ──────────► │ │
│  └───┴───┴───┴───┴───┘        └───────────────────────┘ │
│  (each tracked separately)     (just bump pointer)      │
│                                                          │
│  free(C) = complex             free(C) = no-op          │
│  must update freelists         (can't free one thing)   │
│                                                          │
│  free all = free each          free all = one operation │
│  O(n) operations               reset pointer to 0       │
└─────────────────────────────────────────────────────────┘
```

### Internal Structure

```
┌─────────────────────────────────────────────────────────┐
│                 ArenaAllocator                           │
├─────────────────────────────────────────────────────────┤
│  child_allocator ──────► (backing allocator, e.g. page) │
│                                                          │
│  state:                                                  │
│    buffer_list ──────► [linked list of buffers]         │
│    end_index: 1847     (next free byte in current buf)  │
└─────────────────────────────────────────────────────────┘

The buffer_list (singly-linked):
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  current ────► ┌────────────────────────────────────┐   │
│                │ Buffer 3 (newest, 12KB)             │   │
│                │ ┌────────────────────────────────┐  │   │
│                │ │████████████████░░░░░░░░░░░░░░░░│  │   │
│                │ │◄── used ──────►◄─ available ──►│  │   │
│                │ │            end_index=1847       │  │   │
│                │ └────────────────────────────────┘  │   │
│                │ next ──────────────────────────────────┐│
│                └────────────────────────────────────┘   ││
│                                                         ▼│
│                ┌────────────────────────────────────┐   │
│                │ Buffer 2 (8KB) - FULL              │   │
│                │ ████████████████████████████████████│   │
│                │ next ──────────────────────────────────┐│
│                └────────────────────────────────────┘   ││
│                                                         ▼│
│                ┌────────────────────────────────────┐   │
│                │ Buffer 1 (oldest, 4KB) - FULL      │   │
│                │ ████████████████████████████████████│   │
│                │ next ──► null                       │   │
│                └────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

### Step-by-Step: What Happens During Allocation

Let's trace `arena.allocator().alloc(u32, 10)` (40 bytes):

```
State before:
┌─────────────────────────────────────────────────────────┐
│ Buffer (4096 bytes total)                                │
│ ┌───────────────────────────────────────────────────────┐│
│ │███████████████████████████████░░░░░░░░░░░░░░░░░░░░░░░││
│ │                              ▲                        ││
│ │                         end_index=2048                ││
│ └───────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘

Step 1: Calculate aligned position
        - Need 40 bytes for 10 × u32
        - u32 requires 4-byte alignment
        - end_index=2048 is already 4-byte aligned ✓

Step 2: Check if it fits
        - 2048 + 40 = 2088
        - 2088 < 4096 ✓ (fits in current buffer)

Step 3: Bump the pointer
        - Return pointer to byte 2048
        - Update end_index = 2088

State after:
┌─────────────────────────────────────────────────────────┐
│ Buffer (4096 bytes total)                                │
│ ┌───────────────────────────────────────────────────────┐│
│ │███████████████████████████████████████░░░░░░░░░░░░░░░││
│ │                              ◄40 bytes►▲              ││
│ │                              (your u32s) end_index=2088│
│ └───────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### What If It Doesn't Fit?

```
State before: Buffer almost full
┌─────────────────────────────────────────────────────────┐
│ Buffer 1 (4096 bytes)                                    │
│ ███████████████████████████████████████████████████████░░│
│                                              end_index=4090│
└─────────────────────────────────────────────────────────┘

Request: alloc(u8, 100)  // 100 bytes needed

Step 1: Check fit → 4090 + 100 = 4190 > 4096 ✗ DOESN'T FIT

Step 2: Allocate NEW buffer from child_allocator
        - New size = old_size × 1.5 = 6144 bytes (growth factor)

Step 3: Prepend new buffer to list

State after:
┌─────────────────────────────────────────────────────────┐
│ Buffer 2 (6144 bytes) ← NEW, now current                 │
│ ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│ ◄100 bytes►                                 end_index=100│
│ next ─────────────────────────┐                          │
└───────────────────────────────┼──────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────┐
│ Buffer 1 (4096 bytes) ← OLD, kept for later deinit      │
│ █████████████████████████████████████████████████████████│
│ next ──► null                                            │
└─────────────────────────────────────────────────────────┘
```

### Free Behavior - The Clever Optimization

Individual `free()` is mostly a no-op, BUT there's one exception:

```
If you free the MOST RECENT allocation, arena can reclaim it!

State:
┌─────────────────────────────────────────────────────────┐
│ Buffer                                                   │
│ ██████████████████████████████████████████████████░░░░░░│
│                                 ◄─── last alloc ───►    │
│                                 A (50 bytes)  end=2500  │
└─────────────────────────────────────────────────────────┘

free(A):
- Is A the last allocation? Check: A.ptr + A.len == buffer.ptr + end_index
- YES! We can reclaim by: end_index -= 50

After free(A):
┌─────────────────────────────────────────────────────────┐
│ Buffer                                                   │
│ ████████████████████████████████████████████░░░░░░░░░░░░│
│                                          end=2450       │
└─────────────────────────────────────────────────────────┘

But if you free something that's NOT the last allocation:
- Nothing happens (no-op)
- Memory stays "allocated" until reset/deinit
```

### Reset Modes Visualized

```
┌─────────────────────────────────────────────────────────┐
│                    .free_all                             │
│                                                          │
│  Before:  [Buf3]──►[Buf2]──►[Buf1]──►null               │
│                                                          │
│  Action:  Return ALL buffers to child_allocator          │
│                                                          │
│  After:   null (empty list, end_index=0)                │
│                                                          │
│  Use when: Done with arena, won't use again             │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                 .retain_capacity                         │
│                                                          │
│  Before:  [Buf3]──►[Buf2]──►[Buf1]──►null               │
│           end_index=5000                                 │
│                                                          │
│  Action:  Keep all buffers, just reset end_index         │
│                                                          │
│  After:   [Buf3]──►[Buf2]──►[Buf1]──►null               │
│           end_index=0 (ready to reuse!)                  │
│                                                          │
│  Use when: Loop processing (reuse memory each iteration)│
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│              .retain_with_limit(8192)                    │
│                                                          │
│  Before:  [Buf3 12KB]──►[Buf2 8KB]──►[Buf1 4KB]──►null  │
│                                                          │
│  Action:  Keep up to 8KB, free the rest                  │
│                                                          │
│  After:   [Buf2 8KB]──►null                              │
│           (Buf3 and Buf1 returned to child_allocator)   │
│                                                          │
│  Use when: Want to limit memory retention               │
└─────────────────────────────────────────────────────────┘
```

### Real-World Example: Parser

```zig
pub fn parseFile(source: []const u8) !Ast {
    // Create arena - all AST nodes will live here
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();  // Free EVERYTHING when done

    const allocator = arena.allocator();

    // Parse creates hundreds of AST nodes
    // Each node is just a bump allocation - super fast!
    var root = try parseExpression(allocator, source);

    // Process the AST...
    try analyze(root);
    try codegen(root);

    // When function returns: arena.deinit() frees ALL nodes at once
    // No need to walk the tree and free each node!
}
```

### When to Use Arena

```
┌─────────────────────────────────────────────────────────┐
│ PERFECT for:                  │ AVOID for:              │
├───────────────────────────────┼─────────────────────────┤
│ ✓ Parsing (AST nodes)         │ ✗ Long-lived objects    │
│ ✓ HTTP request handling       │ ✗ Need to free one item │
│ ✓ Game frame allocations      │ ✗ Unpredictable lifetime│
│ ✓ Compiler passes             │                         │
│ ✓ Tree/graph building         │                         │
└───────────────────────────────┴─────────────────────────┘

Speed: VERY FAST (just pointer bump)
Memory: Grows as needed, freed all at once
```

---

## 3. FixedBufferAllocator - Zero Heap Allocations

**Source:** `std/heap/FixedBufferAllocator.zig` (231 lines)
**Access:** `std.heap.FixedBufferAllocator`

### The Simple Idea

Like ArenaAllocator, but uses a buffer YOU provide. Zero heap allocations ever.

```
┌─────────────────────────────────────────────────────────┐
│ ArenaAllocator:              FixedBufferAllocator:       │
│                                                          │
│ Gets memory from             Uses YOUR buffer            │
│ child_allocator              (stack, static, embedded)   │
│       ↓                              ↓                   │
│ ┌───────────┐                ┌───────────────────────┐  │
│ │ Heap/OS   │                │ var buf: [4096]u8;    │  │
│ └───────────┘                │ // lives on stack     │  │
│                              └───────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Internal Structure - Minimal!

```zig
const FixedBufferAllocator = struct {
    end_index: usize,   // Where next allocation goes
    buffer: []u8,       // Your buffer
};
```

That's literally it. Two fields.

### Step-by-Step Allocation

```
Your code:
    var buf: [1024]u8 = undefined;
    var fba = FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    const a = try allocator.alloc(u8, 100);
    const b = try allocator.alloc(u32, 10);  // 40 bytes, needs 4-byte align
    const c = try allocator.alloc(u8, 200);

Memory layout after each allocation:

After alloc(u8, 100):
┌────────────────────────────────────────────────────────────┐
│ buf[0..1024]                                                │
│ ████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ◄─── a: 100 bytes ──►                                       │
│                      ▲                                      │
│                 end_index=100                               │
└────────────────────────────────────────────────────────────┘

After alloc(u32, 10): [needs 4-byte alignment!]
┌────────────────────────────────────────────────────────────┐
│ buf[0..1024]                                                │
│ ████████████████████░░░░████████████████░░░░░░░░░░░░░░░░░░ │
│ ◄─── a: 100 ──────►    ◄─── b: 40 ─────►                   │
│                    ▲pad▲                ▲                   │
│                   (align to 4)     end_index=144            │
└────────────────────────────────────────────────────────────┘

After alloc(u8, 200):
┌────────────────────────────────────────────────────────────┐
│ buf[0..1024]                                                │
│ ████████████████████░░░░████████████████████████████████░░ │
│ ◄─── a ────►      ◄─── b ────►◄────── c: 200 ───────►     │
│                                                     ▲       │
│                                               end_index=344 │
└────────────────────────────────────────────────────────────┘
```

### What Happens on OutOfMemory?

```
State: end_index=900, buffer size=1024

Request: alloc(u8, 200)

Check: 900 + 200 = 1100 > 1024  ✗ DOESN'T FIT

Result: Returns null (allocation failed)
        No panic, no abort - just null

Your code must handle this:
    const ptr = allocator.alloc(u8, 200) orelse {
        // Handle out of memory
        return error.OutOfMemory;
    };
```

### Thread-Safe Variant (Lock-Free!)

FixedBufferAllocator offers a thread-safe allocator using atomics:

```
Regular allocator:             Thread-safe allocator:
┌─────────────────────────┐   ┌─────────────────────────┐
│ fba.allocator()         │   │ fba.threadSafeAllocator()│
│                         │   │                         │
│ end_index += size;      │   │ CAS loop:               │
│ (not safe if multiple   │   │   load end_index        │
│  threads!)              │   │   try CAS to new value  │
│                         │   │   retry if failed       │
└─────────────────────────┘   └─────────────────────────┘
```

The lock-free code:
```zig
fn threadSafeAlloc(...) ?[*]u8 {
    var end_index = @atomicLoad(usize, &self.end_index, .seq_cst);
    while (true) {
        // Calculate what we need
        const new_end_index = end_index + aligned_size;
        if (new_end_index > self.buffer.len) return null;

        // Try to claim it atomically
        end_index = @cmpxchgWeak(
            usize,
            &self.end_index,
            end_index,      // expected old value
            new_end_index,  // new value to write
            .seq_cst, .seq_cst
        ) orelse return self.buffer[aligned_index..new_end_index].ptr;
        // If CAS failed (another thread beat us), loop and retry
    }
}
```

### Compile-Time Usage

FixedBufferAllocator works at comptime!

```zig
const my_data = comptime blk: {
    var buffer: [1024]u8 = undefined;
    var fba = FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    // This runs at compile time!
    var list = std.ArrayList(u32).init(allocator);
    list.appendSlice(&[_]u32{ 1, 2, 3, 4, 5 }) catch unreachable;

    break :blk list.items;
};
// my_data is baked into the binary at compile time
```

### When to Use FixedBufferAllocator

```
┌─────────────────────────────────────────────────────────┐
│ PERFECT for:                  │ AVOID for:              │
├───────────────────────────────┼─────────────────────────┤
│ ✓ Embedded systems (no heap!) │ ✗ Unknown size needs    │
│ ✓ Stack-based scratch space   │ ✗ When you need growth  │
│ ✓ Compile-time allocation     │                         │
│ ✓ Performance-critical paths  │                         │
│ ✓ Deterministic memory usage  │                         │
└───────────────────────────────┴─────────────────────────┘

Speed: BLAZING FAST (just pointer arithmetic)
Memory: Fixed size, you control exactly how much
```

---

## 4. DebugAllocator - The Memory Detective

**Source:** `std/heap/debug_allocator.zig` (1428 lines)
**Access:** `std.heap.DebugAllocator` (formerly GeneralPurposeAllocator)

### The Simple Idea

A slow allocator that catches memory bugs. It tracks every allocation and catches:
- Memory leaks (forgot to free)
- Double frees (freed same memory twice)
- Use-after-free (using memory after freeing it)

### How It Catches Bugs

```
┌─────────────────────────────────────────────────────────┐
│                    NORMAL ALLOCATOR                      │
│                                                          │
│  alloc(100) ──► returns ptr 0x1000                      │
│  free(0x1000) ──► memory returned to pool               │
│  alloc(100) ──► might return 0x1000 again! (reused)     │
│                                                          │
│  Problem: If you use 0x1000 after free, it might        │
│           "work" because memory was reused. Bug hidden! │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    DEBUG ALLOCATOR                       │
│                                                          │
│  alloc(100):                                             │
│    1. Get memory                                         │
│    2. Record: "0x1000 allocated at main.zig:42"         │
│    3. Return ptr                                         │
│                                                          │
│  free(0x1000):                                           │
│    1. Check: was this actually allocated? ✓             │
│    2. Record: "0x1000 freed at main.zig:87"             │
│    3. POISON the memory (fill with 0xAA)                │
│    4. DON'T reuse this address (never_reuse mode)       │
│                                                          │
│  If you use 0x1000 after free:                          │
│    - Memory is poisoned (reads return garbage)          │
│    - Crash with helpful message!                        │
│                                                          │
│  If you free(0x1000) again:                             │
│    - Allocator sees "already freed!"                    │
│    - Prints 3 stack traces:                             │
│      1. Where you allocated                             │
│      2. Where you first freed                           │
│      3. Where you freed again (the bug!)                │
└─────────────────────────────────────────────────────────┘
```

### Internal Structure - Bucket System

Small allocations use "buckets" - pages divided into same-size slots:

```
┌─────────────────────────────────────────────────────────┐
│                SIZE CLASS BUCKETS                        │
│                                                          │
│  Size Class 0 (1 byte):     Size Class 3 (8 bytes):     │
│  ┌─┬─┬─┬─┬─┬─┬─┬─┐         ┌────────┬────────┬────────┐ │
│  │1│1│1│1│1│1│1│1│         │   8    │   8    │   8    │ │
│  └─┴─┴─┴─┴─┴─┴─┴─┘         └────────┴────────┴────────┘ │
│                                                          │
│  Size Class 4 (16 bytes):   Size Class 5 (32 bytes):    │
│  ┌────────────────┐         ┌────────────────────────┐  │
│  │       16       │         │           32           │  │
│  └────────────────┘         └────────────────────────┘  │
│                                                          │
│  Each bucket is a PAGE containing:                       │
│  ┌──────────────────────────────────────────────────┐   │
│  │ BucketHeader                                      │   │
│  │   - alloc_cursor (which slot next)               │   │
│  │   - used_bits (1 bit per slot: allocated?)       │   │
│  │   - stack_traces[] (where each slot allocated)   │   │
│  ├──────────────────────────────────────────────────┤   │
│  │ Slot 0 │ Slot 1 │ Slot 2 │ Slot 3 │ ...          │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Allocation Flow

```
Request: alloc(u8, 20)

Step 1: Find size class
        20 bytes → round up to power of 2 → 32 bytes → class 5

Step 2: Get bucket for class 5
        ┌──────────────────────────────────────────────────┐
        │ Bucket for 32-byte slots                         │
        │ ┌──────┬──────┬──────┬──────┬──────┬──────┐     │
        │ │ used │ used │ FREE │ used │ FREE │ ...  │     │
        │ └──────┴──────┴──────┴──────┴──────┴──────┘     │
        │ used_bits: 1 1 0 1 0 ...                         │
        │                 ▲                                │
        │            pick this one                         │
        └──────────────────────────────────────────────────┘

Step 3: Mark slot as used, capture stack trace
        used_bits[2] = 1
        stack_traces[2] = captureStackTrace()

Step 4: Return pointer to slot 2
```

### Leak Detection on deinit()

```zig
var gpa = std.heap.DebugAllocator(.{}){};
defer {
    const check = gpa.deinit();
    if (check == .leak) {
        // Leaks detected! Stack traces printed.
    }
}

const allocator = gpa.allocator();
const data = try allocator.alloc(u8, 100);
// Oops! Forgot to free(data)

// On deinit, allocator walks all buckets:
//   For each slot where used_bit == 1:
//     Print: "LEAK! Allocated at: [stack trace]"
```

### Configuration Options

```zig
var gpa = std.heap.DebugAllocator(.{
    // How many stack frames to capture (more = slower but more info)
    .stack_trace_frames = 10,

    // Track total bytes allocated (useful for memory budgets)
    .enable_memory_limit = true,

    // Keep freed memory mapped (helps detect use-after-free)
    .never_unmap = true,

    // Print every alloc/free (very verbose!)
    .verbose_log = true,
}){};
```

### When to Use DebugAllocator

```
┌─────────────────────────────────────────────────────────┐
│ PERFECT for:                  │ NEVER use for:          │
├───────────────────────────────┼─────────────────────────┤
│ ✓ Development builds          │ ✗ Production/Release    │
│ ✓ Finding memory leaks        │ ✗ Performance-sensitive │
│ ✓ Debugging double-free       │ ✗ Memory-constrained    │
│ ✓ Debugging use-after-free    │                         │
│ ✓ CI/testing environments     │                         │
└───────────────────────────────┴─────────────────────────┘

Speed: SLOW (captures stack traces, maintains metadata)
Memory: HIGH overhead (100+ bytes per allocation)
Value: PRICELESS when debugging memory bugs
```

---

## 5. SmpAllocator - Multi-Threaded Production

**Source:** `std/heap/SmpAllocator.zig` (224 lines)
**Access:** `std.heap.smp_allocator`

### The Simple Idea

Each thread gets its own freelist. No lock contention in the common case.

```
┌─────────────────────────────────────────────────────────┐
│              TRADITIONAL MULTI-THREADED                  │
│                                                          │
│   Thread 1 ─────┐                                        │
│                 ├──► [Single Freelist] ◄── Lock!        │
│   Thread 2 ─────┤         ▲                              │
│                 │     contention                         │
│   Thread 3 ─────┘                                        │
│                                                          │
│   Every alloc/free = lock acquisition = SLOW            │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    SMP ALLOCATOR                         │
│                                                          │
│   Thread 1 ──────► [Freelist 1] ◄── usually no lock!    │
│                                                          │
│   Thread 2 ──────► [Freelist 2] ◄── usually no lock!    │
│                                                          │
│   Thread 3 ──────► [Freelist 3] ◄── usually no lock!    │
│                                                          │
│   Each thread prefers its own freelist                   │
│   Lock only needed if another thread has what we need    │
└─────────────────────────────────────────────────────────┘
```

### Internal Structure

```
┌─────────────────────────────────────────────────────────┐
│                 GLOBAL STATE (singleton)                 │
│                                                          │
│   threads[0..128]:  Array of Thread structs              │
│   cpu_count:        Actual number of CPUs                │
│                                                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ threads[0]                threads[1]                 │ │
│ │ ┌─────────────────┐      ┌─────────────────┐        │ │
│ │ │ mutex           │      │ mutex           │        │ │
│ │ │ next_addrs[14]  │      │ next_addrs[14]  │        │ │
│ │ │ frees[14]       │      │ frees[14]       │        │ │
│ │ └─────────────────┘      └─────────────────┘        │ │
│ │                                                      │ │
│ │ threads[2]                 ...threads[127]          │ │
│ │ ┌─────────────────┐      ┌─────────────────┐        │ │
│ │ │ mutex           │      │ mutex           │        │ │
│ │ │ next_addrs[14]  │      │ next_addrs[14]  │        │ │
│ │ │ frees[14]       │      │ frees[14]       │        │ │
│ │ └─────────────────┘      └─────────────────┘        │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                          │
│ threadlocal var thread_index: u32;  // Which slot I use  │
└─────────────────────────────────────────────────────────┘

Each thread slot has 14 SIZE CLASSES:
  Class 0:  8-byte slots
  Class 1:  16-byte slots
  Class 2:  32-byte slots
  ...
  Class 13: 64KB slots (slab_len)

  Anything larger → goes directly to PageAllocator
```

### Allocation Flow - The Lock Rotation Trick

```
Thread A wants to allocate 50 bytes:

Step 1: What's my slot?
        thread_index = 3 (threadlocal variable)

Step 2: Try to lock my slot
        ┌────────────────────────────────────────────────┐
        │ threads[3].mutex.tryLock()                     │
        │                                                 │
        │ SUCCESS? ──► Great! Use this slot's freelist   │
        │                                                 │
        │ FAILED? ──► Someone else has it, try next slot │
        └────────────────────────────────────────────────┘

Step 3: (If failed) Try slot 4, then 5, then 6...
        for (i in 0..cpu_count) {
            slot = (thread_index + i) % cpu_count;
            if (threads[slot].mutex.tryLock()) {
                thread_index = slot;  // Remember for next time
                break;
            }
        }

Step 4: Got a slot! Now allocate from its freelist
        ┌────────────────────────────────────────────────┐
        │ 50 bytes → size class 6 (64 bytes)             │
        │                                                 │
        │ Check frees[6]:                                │
        │   If non-null: Pop from freelist, return it    │
        │   If null: Bump next_addrs[6], return that     │
        │                                                 │
        │ If next_addrs[6] hits page boundary:           │
        │   Get fresh 64KB slab from PageAllocator       │
        └────────────────────────────────────────────────┘

Step 5: Unlock and return
```

### Freelist Structure

```
┌─────────────────────────────────────────────────────────┐
│              SIZE CLASS 4 (32-byte slots)                │
│                                                          │
│  frees[4] ──► ┌──────────────────────────────────┐      │
│               │ freed slot at 0x1000              │      │
│               │ ┌────────────────────────────┐   │      │
│               │ │ next ──────────────────────────────┐  │
│               │ │ (rest is garbage/old data)  │   │  │  │
│               │ └────────────────────────────┘   │  │  │
│               └──────────────────────────────────┘  │  │
│                                                     ▼  │
│               ┌──────────────────────────────────┐     │
│               │ freed slot at 0x2000              │     │
│               │ next ────────────────────────────────┐  │
│               └──────────────────────────────────┘   │  │
│                                                      ▼  │
│               ┌──────────────────────────────────┐      │
│               │ freed slot at 0x3000              │      │
│               │ next ──► null                     │      │
│               └──────────────────────────────────┘      │
│                                                          │
│  On alloc: pop 0x1000, frees[4] now points to 0x2000    │
│  On free:  push to front, freed ptr's first bytes = old │
│            frees[4], then frees[4] = freed ptr          │
└─────────────────────────────────────────────────────────┘
```

### When to Use SmpAllocator

```
┌─────────────────────────────────────────────────────────┐
│ PERFECT for:                  │ Consider alternatives:  │
├───────────────────────────────┼─────────────────────────┤
│ ✓ Production servers          │ • Single-threaded app:  │
│ ✓ Multi-threaded workloads    │   just use Arena        │
│ ✓ High-throughput systems     │                         │
│ ✓ When you need speed         │ • Debugging:            │
│                               │   use DebugAllocator    │
└───────────────────────────────┴─────────────────────────┘

Speed: FAST (usually lock-free)
Scalability: Excellent (per-thread freelists)
```

---

## 6. MemoryPool - Object Pool Pattern

**Source:** `std/heap/memory_pool.zig` (223 lines)
**Access:** `std.heap.MemoryPool`

### The Simple Idea

When you need LOTS of objects of the SAME type, a pool is faster than a general allocator.

```
┌─────────────────────────────────────────────────────────┐
│            GENERAL ALLOCATOR (ArrayList, etc.)           │
│                                                          │
│  Each alloc: Find free space of right size              │
│  Each free:  Update complex metadata structures         │
│  Problem:    Overhead for each operation                 │
│                                                          │
│  Memory layout (fragmented):                             │
│  ┌──┬────┬──┬──────┬─┬───┬────┬──┐                      │
│  │A │ B  │A │  C   │A│ D │free│A │                      │
│  └──┴────┴──┴──────┴─┴───┴────┴──┘                      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                   MEMORY POOL                            │
│                                                          │
│  All objects same size = simple freelist                 │
│  Alloc: Pop from list (O(1))                            │
│  Free:  Push to list (O(1))                             │
│                                                          │
│  Memory layout (uniform):                                │
│  ┌────┬────┬────┬────┬────┬────┬────┬────┐             │
│  │ T  │ T  │free│ T  │free│ T  │ T  │free│             │
│  └────┴────┴────┴────┴────┴────┴────┴────┘             │
│  All slots exactly sizeof(T) - perfect cache behavior!  │
└─────────────────────────────────────────────────────────┘
```

### Internal Structure

```
MemoryPool(Entity):
┌─────────────────────────────────────────────────────────┐
│  arena: ArenaAllocator   ← backing storage (grows)      │
│                                                          │
│  free_list ──► ┌──────────────────┐                     │
│                │ destroyed Entity │                     │
│                │ .next ─────────────┐                   │
│                └──────────────────┘ │                   │
│                                     ▼                   │
│                ┌──────────────────┐                     │
│                │ destroyed Entity │                     │
│                │ .next ─────────────┐                   │
│                └──────────────────┘ │                   │
│                                     ▼                   │
│                               null                      │
└─────────────────────────────────────────────────────────┘

The TRICK: When an Entity is destroyed, we reuse its memory
as a freelist node! The first bytes become a 'next' pointer.

┌──────────────────────────────────────────────────────────┐
│            SAME MEMORY, TWO INTERPRETATIONS              │
│                                                          │
│  When ALIVE (Entity):        When DESTROYED (Node):      │
│  ┌────────────────────┐      ┌────────────────────┐     │
│  │ x: f32 = 1.5       │      │ next: *Node ───────────►  │
│  │ y: f32 = 2.0       │      │ (garbage)          │     │
│  │ health: u32 = 100  │      │ (garbage)          │     │
│  │ name: []u8 = ...   │      │ (garbage)          │     │
│  └────────────────────┘      └────────────────────┘     │
│                                                          │
│  Pool does @ptrCast between these views!                │
└──────────────────────────────────────────────────────────┘
```

### create() and destroy() Flow

```
pool.create():

┌─────────────────────────────────────────────────────────┐
│  Is free_list non-null?                                  │
│  ┌───────────────────────────────────────────────────┐  │
│  │ YES: Pop first node                               │  │
│  │      ptr = free_list                              │  │
│  │      free_list = ptr.next                         │  │
│  │      return @ptrCast(*Entity, ptr)                │  │
│  └───────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────┐  │
│  │ NO: Allocate fresh from arena                     │  │
│  │     ptr = arena.alloc(Entity, 1)                  │  │
│  │     return ptr                                    │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘

pool.destroy(entity_ptr):

┌─────────────────────────────────────────────────────────┐
│  1. Reinterpret entity memory as a freelist Node        │
│     node = @ptrCast(*Node, entity_ptr)                  │
│                                                          │
│  2. Push onto freelist                                   │
│     node.next = free_list                                │
│     free_list = node                                     │
│                                                          │
│  Memory NOT returned to arena!                           │
│  Just added to freelist for reuse.                       │
└─────────────────────────────────────────────────────────┘
```

### Visual Example

```
Initial: Empty pool
  arena: [empty]
  free_list: null

After create() x3:
  arena: [Entity0][Entity1][Entity2]
  free_list: null

  returned: ptr0, ptr1, ptr2

After destroy(ptr1):
  arena: [Entity0][FREED  ][Entity2]
  free_list ──────────►[ptr1.next=null]

After destroy(ptr0):
  arena: [FREED  ][FREED  ][Entity2]
  free_list ──►[ptr0.next=ptr1]──►[ptr1.next=null]

After create():
  Pop ptr0 from freelist!
  arena: [Entity0][FREED  ][Entity2]  ← ptr0 reused!
  free_list ──►[ptr1.next=null]

  returned: ptr0 (same address, fresh Entity!)
```

### Preheating for Deterministic Behavior

```zig
// Pre-allocate 1000 entities at startup
var pool = try MemoryPool(Entity).initPreheated(allocator, 1000);

// Now: 1000 entities on freelist, ready to go
// create() will be instant for first 1000 calls
// No allocations during gameplay!

// For hard limits (embedded/games):
var pool = try MemoryPoolExtra(Entity, .{ .growable = false })
    .initPreheated(allocator, 100);

// Can ONLY have 100 entities max
// 101st create() returns OutOfMemory
```

### When to Use MemoryPool

```
┌─────────────────────────────────────────────────────────┐
│ PERFECT for:                  │ AVOID for:              │
├───────────────────────────────┼─────────────────────────┤
│ ✓ Game entities               │ ✗ Mixed-type objects    │
│ ✓ Network connections         │ ✗ Varying sizes         │
│ ✓ Parser AST nodes            │ ✗ Few allocations       │
│ ✓ ECS components              │                         │
│ ✓ Any "lots of same thing"    │                         │
└───────────────────────────────┴─────────────────────────┘

Speed: VERY FAST (O(1) alloc/free, cache-friendly)
Memory: Efficient (no per-object overhead)
```

---

## 7. ThreadSafeAllocator - Simple Wrapper

**Source:** `std/heap/ThreadSafeAllocator.zig` (56 lines)

### The Simple Idea

Wrap ANY allocator with a mutex. Simple but adds lock contention.

```
┌─────────────────────────────────────────────────────────┐
│                                                          │
│   Your allocator:            ThreadSafeAllocator:       │
│   ┌───────────────┐          ┌───────────────────────┐  │
│   │ ArenaAllocator│          │ mutex                 │  │
│   │ (not safe!)   │    ───►  │ child: ArenaAllocator │  │
│   └───────────────┘          └───────────────────────┘  │
│                                                          │
│   Every operation now:                                   │
│     1. Lock mutex                                        │
│     2. Call child allocator                              │
│     3. Unlock mutex                                      │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### The Entire Implementation

```zig
child_allocator: Allocator,
mutex: std.Thread.Mutex = .{},

fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    const self: *ThreadSafeAllocator = @ptrCast(@alignCast(ctx));
    self.mutex.lock();
    defer self.mutex.unlock();
    return self.child_allocator.rawAlloc(n, alignment, ra);
}
// resize, remap, free are identical pattern
```

That's it! ~50 lines total.

### When to Use

```
┌─────────────────────────────────────────────────────────┐
│ Use ThreadSafeAllocator when:                           │
│   • Quick fix to make something thread-safe             │
│   • Low-contention scenarios                            │
│   • Wrapping a custom allocator                         │
│                                                          │
│ Use SmpAllocator instead when:                          │
│   • High throughput needed                              │
│   • Many threads allocating frequently                  │
│   • Production server workloads                         │
└─────────────────────────────────────────────────────────┘
```

---

## 8-11. Specialized Allocators (Brief)

### WasmAllocator
For WebAssembly targets. Uses `@wasmMemoryGrow` builtin.
```
Only use: When compiling to wasm32/wasm64
```

### SbrkAllocator
For Plan9 OS and sbrk-style memory.
```
Only use: Plan9 or custom embedded with sbrk
```

### c_allocator / raw_c_allocator
Wraps C's malloc/free.
```
Use: When interfacing with C libraries
raw_c_allocator: Faster but only supports max_align_t
c_allocator: Full alignment support
```

### StackFallbackAllocator
Stack buffer with heap fallback.
```zig
var stack_alloc = std.heap.stackFallback(4096, page_allocator);
// First 4KB from stack, overflow goes to page_allocator
```

---

## Quick Reference: Which Allocator?

```
┌─────────────────────────────────────────────────────────┐
│                  DECISION FLOWCHART                      │
│                                                          │
│  Is this for debugging?                                  │
│  └─► YES ──► DebugAllocator                             │
│  └─► NO ───┐                                            │
│            ▼                                             │
│  Do you free everything at once?                        │
│  └─► YES ──► ArenaAllocator                             │
│  └─► NO ───┐                                            │
│            ▼                                             │
│  Is it many objects of same type?                       │
│  └─► YES ──► MemoryPool                                 │
│  └─► NO ───┐                                            │
│            ▼                                             │
│  Do you have a fixed buffer?                            │
│  └─► YES ──► FixedBufferAllocator                       │
│  └─► NO ───┐                                            │
│            ▼                                             │
│  Is it multi-threaded?                                  │
│  └─► YES ──► smp_allocator                              │
│  └─► NO ──► page_allocator or c_allocator               │
└─────────────────────────────────────────────────────────┘
```

---

## Summary

Each allocator has a specific purpose:

| Allocator | One-Line Summary |
|-----------|------------------|
| PageAllocator | Direct OS syscalls, foundation for others |
| ArenaAllocator | Bump pointer, free everything at once |
| FixedBufferAllocator | Your buffer, zero heap allocations |
| DebugAllocator | Find memory bugs (leaks, double-free) |
| SmpAllocator | Multi-threaded production workloads |
| MemoryPool | Many objects of same type |
| ThreadSafeAllocator | Add mutex to any allocator |

The key insight: **Zig gives you the building blocks to compose exactly the memory strategy you need.** No hidden allocations, no one-size-fits-all garbage collector - just explicit, understandable memory management.
