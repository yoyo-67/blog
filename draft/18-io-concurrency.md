---
title: "Part 18: IO, Concurrency & Parallelism - A Deep Dive"
date: 2024-01-15
series: ["Zig Internals"]
series_order: 18
tags: ["zig", "io", "concurrency", "threads", "io_uring", "futex", "mutex"]
---

This article explores Zig 0.15's IO system, threading model, synchronization primitives, and async IO support. We'll build understanding from first principles, with visual diagrams and step-by-step traces of the actual source code.

---

## Part 0: Concurrency vs Parallelism - The Foundation

Before diving into code, we need crystal-clear mental models. These terms are often confused.

### The Coffee Shop Analogy

Imagine you're running a coffee shop:

```
CONCURRENCY (One Barista, Many Orders):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   Single Barista handling multiple orders by switching between them │
│                                                                     │
│   ┌─────────┐                                                       │
│   │ Barista │ ◄── Only ONE person                                   │
│   └────┬────┘                                                       │
│        │                                                            │
│   ┌────▼────────────────────────────────────────────────────┐       │
│   │  Timeline:                                              │       │
│   │                                                         │       │
│   │  Order A: [Grind].....[Pour].....      [Serve]          │       │
│   │  Order B:       [Grind].....[Pour].....[Serve]          │       │
│   │  Order C:             [Grind].....[Pour].....[Serve]    │       │
│   │                                                         │       │
│   │  While waiting for milk to steam, start grinding next   │       │
│   └─────────────────────────────────────────────────────────┘       │
│                                                                     │
│   The barista INTERLEAVES tasks - never truly doing two at once     │
│   But customers feel like they're being served "simultaneously"     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

PARALLELISM (Multiple Baristas, Multiple Orders):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   Multiple Baristas actually working AT THE SAME TIME               │
│                                                                     │
│   ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐          │
│   │ Barista 1 │ │ Barista 2 │ │ Barista 3 │ │ Barista 4 │          │
│   └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘          │
│         │             │             │             │                 │
│   ┌─────▼─────────────▼─────────────▼─────────────▼─────┐          │
│   │  Timeline (same moment in time):                    │          │
│   │                                                     │          │
│   │  Barista 1: [Making Latte     ]                     │          │
│   │  Barista 2: [Making Cappuccino]                     │          │
│   │  Barista 3: [Making Espresso  ]                     │          │
│   │  Barista 4: [Making Mocha     ]                     │          │
│   │             ↑                                       │          │
│   │             All happening RIGHT NOW                 │          │
│   └─────────────────────────────────────────────────────┘          │
│                                                                     │
│   TRUE simultaneous execution - 4 drinks being made at once         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Mapping to Computers

```
CONCURRENCY = Managing multiple tasks (may use 1 CPU core)
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   Single CPU Core                                                   │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │  ████  Thread A                                              │  │
│   │      ████  Thread B                                          │  │
│   │          ████  Thread A                                      │  │
│   │              ████  Thread B                                  │  │
│   │                  ████  Thread A                              │  │
│   └──────────────────────────────────────────────────────────────┘  │
│      Time ───────────────────────────────────────────────────────►  │
│                                                                     │
│   The OS scheduler rapidly switches between threads                 │
│   Each switch is called a "context switch" (~1-10 microseconds)     │
│                                                                     │
│   WHY DO THIS?                                                      │
│   • Thread A might be waiting for disk (milliseconds)               │
│   • Instead of wasting CPU time waiting, run Thread B               │
│   • Makes efficient use of CPU while waiting for slow operations    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

PARALLELISM = Actually executing simultaneously (requires multiple CPU cores)
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   Core 0: ████████████████████████  Thread A running                │
│   Core 1: ████████████████████████  Thread B running                │
│   Core 2: ████████████████████████  Thread C running                │
│   Core 3: ████████████████████████  Thread D running                │
│           ↑                                                         │
│           Same instant in time - truly simultaneous                 │
│                                                                     │
│   Time ───────────────────────────────────────────────────────────► │
│                                                                     │
│   WHY DO THIS?                                                      │
│   • CPU-bound work (compression, encryption, math)                  │
│   • 4 cores = potentially 4x speedup                                │
│   • No waiting involved - pure computation                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The Key Insight

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CHOOSING THE RIGHT TOOL                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  QUESTION: What is your program WAITING for?                        │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ Waiting for EXTERNAL things?          → Use ASYNC IO        │    │
│  │ (network, disk, user input)             (concurrency)       │    │
│  │                                                             │    │
│  │ Examples:                                                   │    │
│  │ • Web server waiting for requests                           │    │
│  │ • Database waiting for queries                              │    │
│  │ • File downloader waiting for data                          │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ Doing COMPUTATION?                    → Use THREADS         │    │
│  │ (CPU is the bottleneck)                 (parallelism)       │    │
│  │                                                             │    │
│  │ Examples:                                                   │    │
│  │ • Image processing                                          │    │
│  │ • Video encoding                                            │    │
│  │ • Scientific calculations                                   │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ BOTH waiting AND computing?           → Use THREAD POOL     │    │
│  │                                         + ASYNC IO          │    │
│  │                                                             │    │
│  │ Examples:                                                   │    │
│  │ • Web server that does image processing                     │    │
│  │ • Game server with physics calculations                     │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: The New IO Interface

Zig 0.15 completely redesigned IO. Let's understand WHY and HOW.

### The Problem with the Old Design

```
OLD DESIGN: Every single byte goes through a function pointer
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   Your Code                    GenericReader                        │
│   ┌─────────┐                  ┌─────────────────────┐              │
│   │ read()  │ ──────────────►  │ readFn() pointer    │              │
│   │ read()  │ ──────────────►  │ readFn() pointer    │              │
│   │ read()  │ ──────────────►  │ readFn() pointer    │   SLOW!      │
│   │ read()  │ ──────────────►  │ readFn() pointer    │   Every      │
│   │ read()  │ ──────────────►  │ readFn() pointer    │   byte!      │
│   └─────────┘                  └─────────────────────┘              │
│                                                                     │
│   Problem: Function pointers are INDIRECT calls                     │
│   • CPU can't predict where to jump                                 │
│   • Cache misses on every call                                      │
│   • Branch predictor gets confused                                  │
│                                                                     │
│   Reading 1MB = 1 million indirect function calls!                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The New Design: Buffered + VTable

```
NEW DESIGN: Buffer bytes, only call VTable when buffer is empty
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   Your Code           Reader (with buffer)                          │
│   ┌─────────┐         ┌──────────────────────────────────┐          │
│   │ read()  │ ──────► │ ┌────────────────────────────┐   │          │
│   │ read()  │ ──────► │ │ A B C D E F G H I J K L M  │   │ ◄─ FAST! │
│   │ read()  │ ──────► │ │ ↑                          │   │   Direct │
│   │ read()  │ ──────► │ │ seek                       │   │   memory │
│   │ read()  │ ──────► │ └────────────────────────────┘   │   access │
│   └─────────┘         │            Buffer                │          │
│                       │                                  │          │
│                       │  Buffer empty? ─────────────────►│ VTable   │
│                       │                    (rare!)       │ call     │
│                       └──────────────────────────────────┘          │
│                                                                     │
│   Most reads: buffer[seek++]  ← Just incrementing an integer!       │
│   VTable only called when buffer needs refilling                    │
│                                                                     │
│   Reading 1MB with 4KB buffer = only 256 VTable calls               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The Reader Structure Explained

From `std/Io/Reader.zig`:

```zig
const Reader = @This();

vtable: *const VTable,  // How to get more data (the "slow path")
buffer: []u8,           // The actual bytes we've buffered
seek: usize,            // Where we are in the buffer (consumed)
end: usize,             // Where valid data ends in buffer
```

Let's visualize what these fields mean:

```
Example: We've read 5 bytes from a 10-byte buffer

buffer (the slice):
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ H │ e │ l │ l │ o │ W │ o │ r │ l │ d │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
  0   1   2   3   4   5   6   7   8   9
              ↑               ↑
            seek=5          end=10

┌─────────────┬─────────────────────────┐
│  Already    │   Available to read     │
│  consumed   │   (buffered data)       │
│  (0..5)     │   (5..10)               │
└─────────────┴─────────────────────────┘

buffer[0..seek]   = "Hello"  ← Already returned to caller
buffer[seek..end] = "World"  ← Ready to return next
buffer[end..]     = ???      ← Undefined (not yet filled)
```

### Step-by-Step: Reading a Byte

Let's trace through `reader.takeByte()`:

```zig
pub fn takeByte(r: *Reader) Error!u8 {
    const result = try peekByte(r);  // Get the byte
    r.seek += 1;                      // Mark it as consumed
    return result;
}

pub fn peekByte(r: *Reader) Error!u8 {
    const buffer = r.buffer[0..r.end];
    const seek = r.seek;

    if (seek < buffer.len) {
        @branchHint(.likely);     // Tell compiler: this is the common case
        return buffer[seek];       // FAST PATH: just return the byte!
    }

    try fill(r, 1);                // SLOW PATH: need more data
    return r.buffer[r.seek];
}
```

**Trace - FAST PATH (data in buffer):**

```
Initial state:
┌───┬───┬───┬───┬───┐
│ A │ B │ C │ D │ E │  buffer
└───┴───┴───┴───┴───┘
  ↑               ↑
seek=0          end=5

Call takeByte():

Step 1: peekByte() checks: seek(0) < end(5)?  YES!
        └─► Return buffer[0] = 'A'

Step 2: seek += 1

Final state:
┌───┬───┬───┬───┬───┐
│ A │ B │ C │ D │ E │  buffer
└───┴───┴───┴───┴───┘
      ↑           ↑
    seek=1      end=5

Returned: 'A'
Time: ~1-2 nanoseconds (just memory access + increment)
```

**Trace - SLOW PATH (buffer empty):**

```
Initial state:
┌───┬───┬───┬───┬───┐
│ A │ B │ C │ D │ E │  buffer
└───┴───┴───┴───┴───┘
                  ↑
              seek=5, end=5  (seek == end means empty!)

Call takeByte():

Step 1: peekByte() checks: seek(5) < end(5)?  NO!
        └─► Need to call fill()

Step 2: fill() calls vtable.stream() to get more data
        ┌─────────────────────────────────────────┐
        │  vtable.stream() reads from source:      │
        │  • File? Read more from disk             │
        │  • Network? Receive more packets         │
        │  • Decompressor? Decompress more bytes   │
        └─────────────────────────────────────────┘

Step 3: Buffer refilled
┌───┬───┬───┬───┬───┐
│ F │ G │ H │ I │ J │  buffer (new data!)
└───┴───┴───┴───┴───┘
  ↑               ↑
seek=0          end=5

Step 4: Return buffer[0] = 'F', seek = 1

Time: ~1000+ nanoseconds (syscall overhead if reading from file)
```

### The VTable - What Happens When Buffer is Empty

```zig
pub const VTable = struct {
    /// Called when we need more data in the buffer
    stream: *const fn (r: *Reader, w: *Writer, limit: Limit) StreamError!usize,

    /// Called when we want to skip data without copying
    discard: *const fn (r: *Reader, limit: Limit) Error!usize,

    /// Called for scatter-gather IO (multiple buffers)
    readVec: *const fn (r: *Reader, data: [][]u8) Error!usize,

    /// Called when buffer needs to be reorganized
    rebase: *const fn (r: *Reader, capacity: usize) RebaseError!void,
};
```

Think of VTable as the Reader asking: "How do I get more bytes?"

```
Different Reader types have different answers:

┌─────────────────────────────────────────────────────────────────────┐
│ FileReader:                                                         │
│   "More bytes? I'll syscall read() from the file descriptor"        │
│                                                                     │
│ NetworkReader:                                                      │
│   "More bytes? I'll syscall recv() from the socket"                 │
│                                                                     │
│ DecompressReader:                                                   │
│   "More bytes? I'll decompress more from the compressed stream"     │
│                                                                     │
│ FixedReader:                                                        │
│   "More bytes? Sorry, I have none - return EndOfStream"             │
└─────────────────────────────────────────────────────────────────────┘
```

### Example: Creating a Fixed Buffer Reader

The simplest case - reading from memory:

```zig
// Create a reader that reads from a string
var r: Reader = .fixed("Hello, World!");

// What does .fixed() do?
pub fn fixed(buffer: []const u8) Reader {
    return .{
        .vtable = &.{
            .stream = endingStream,   // Returns "no more data"
            .discard = endingDiscard,
            .readVec = endingReadVec,
            .rebase = endingRebase,
        },
        .buffer = @constCast(buffer),
        .end = buffer.len,   // All data is already "buffered"
        .seek = 0,           // Start at beginning
    };
}
```

Visual state after creation:

```
r = .fixed("Hello, World!")

┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ H │ e │ l │ l │ o │ , │   │ W │ o │ r │ l │ d │ ! │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
  ↑                                               ↑
seek=0                                         end=13

All data available immediately - vtable never needs to be called!
```

### Zero-Copy Streaming: Reader → Writer

One of the most powerful features - piping data without copying:

```zig
pub fn stream(r: *Reader, w: *Writer, limit: Limit) StreamError!usize {
    const buffer = limit.slice(r.buffer[r.seek..r.end]);

    if (buffer.len > 0) {
        @branchHint(.likely);
        const n = try w.write(buffer);  // Write directly from Reader's buffer!
        r.seek += n;
        return n;
    }

    // Buffer empty - ask VTable to stream directly
    return r.vtable.stream(r, w, limit);
}
```

**What makes this "zero-copy"?**

```
Traditional approach (WITH copying):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Reader           temp buffer          Writer                       │
│  ┌─────────┐      ┌─────────┐         ┌─────────┐                  │
│  │ A B C D │ ──►  │ A B C D │  ──►    │ A B C D │                  │
│  └─────────┘      └─────────┘         └─────────┘                  │
│       1. Copy         2. Copy                                       │
│                                                                     │
│  Data copied TWICE through intermediate buffer                      │
│  Waste of CPU cycles and memory bandwidth                           │
└─────────────────────────────────────────────────────────────────────┘

Zero-copy approach:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Reader's buffer ─────────────────────► Writer                      │
│  ┌─────────┐                           ┌─────────┐                  │
│  │ A B C D │ ─────────────────────────►│ A B C D │                  │
│  └─────────┘                           └─────────┘                  │
│           Direct write from Reader's memory!                        │
│                                                                     │
│  Writer.write() takes a slice - it can be ANY memory                │
│  So we just pass Reader's buffer directly!                          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: The Writer Interface

Writer is the mirror image of Reader - it buffers outgoing data.

### Writer Structure

```zig
vtable: *const VTable,
buffer: []u8,           // Where we accumulate bytes to write
end: usize,             // How many bytes we've written to buffer
```

Visual representation:

```
After writing "Hello":

┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ H │ e │ l │ l │ o │ ? │ ? │ ? │ ? │ ? │  buffer
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                      ↑                ↑
                    end=5          buffer.len=10

buffer[0..end]   = "Hello"  ← Data waiting to be sent
buffer[end..]    = ???      ← Space for more data
```

### Step-by-Step: Writing Bytes

```zig
pub fn write(w: *Writer, bytes: []const u8) Error!usize {
    if (w.end + bytes.len <= w.buffer.len) {
        @branchHint(.likely);  // FAST PATH

        // Copy bytes into our buffer
        @memcpy(w.buffer[w.end..][0..bytes.len], bytes);
        w.end += bytes.len;
        return bytes.len;
    }

    // SLOW PATH: buffer full, need to drain
    return w.vtable.drain(w, &.{bytes}, 1);
}
```

**Trace - FAST PATH (fits in buffer):**

```
Initial state:
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ H │ e │ l │ l │ o │ ? │ ? │ ? │ ? │ ? │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                      ↑
                    end=5

write(", World") - 7 bytes

Step 1: Check: end(5) + len(7) = 12 <= buffer.len(10)?  NO!
        Wait, that's 12 > 10, so this would be SLOW PATH...

Let's try a smaller write:
write("!") - 1 byte

Step 1: Check: end(5) + len(1) = 6 <= buffer.len(10)?  YES!

Step 2: memcpy "!" to buffer[5..6]
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ H │ e │ l │ l │ o │ ! │ ? │ ? │ ? │ ? │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                          ↑
                        end=6

Step 3: end += 1, return 1

Time: ~5-10 nanoseconds (memcpy is fast)
```

**Trace - SLOW PATH (buffer full):**

```
Initial state:
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ H │ e │ l │ l │ o │ , │   │ W │ o │ r │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                                        ↑
                                     end=10 (FULL!)

write("ld!") - 3 bytes

Step 1: Check: end(10) + len(3) = 13 <= buffer.len(10)?  NO!

Step 2: Call vtable.drain()
        ┌─────────────────────────────────────────────────────┐
        │  drain() sends buffer contents to destination:       │
        │  • File? Write to disk                               │
        │  • Network? Send over socket                         │
        │  • Stdout? Print to terminal                         │
        └─────────────────────────────────────────────────────┘

Step 3: After drain, buffer is empty
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ ? │ ? │ ? │ ? │ ? │ ? │ ? │ ? │ ? │ ? │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
  ↑
end=0

Step 4: Now copy "ld!" to buffer
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ l │ d │ ! │ ? │ ? │ ? │ ? │ ? │ ? │ ? │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
              ↑
            end=3

Time: ~1000+ nanoseconds (syscall to write)
```

### Why Buffering Matters: The Syscall Problem

```
WITHOUT buffering (naive approach):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  print("H") → syscall write(fd, "H", 1)  ← Context switch!          │
│  print("e") → syscall write(fd, "e", 1)  ← Context switch!          │
│  print("l") → syscall write(fd, "l", 1)  ← Context switch!          │
│  print("l") → syscall write(fd, "l", 1)  ← Context switch!          │
│  print("o") → syscall write(fd, "o", 1)  ← Context switch!          │
│                                                                     │
│  5 syscalls for 5 bytes = ~5000+ nanoseconds                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

WITH buffering:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  print("H") → buffer[0] = 'H'     ← Just memory write               │
│  print("e") → buffer[1] = 'e'     ← Just memory write               │
│  print("l") → buffer[2] = 'l'     ← Just memory write               │
│  print("l") → buffer[3] = 'l'     ← Just memory write               │
│  print("o") → buffer[4] = 'o'     ← Just memory write               │
│  flush()    → syscall write(fd, "Hello", 5)  ← ONE syscall!         │
│                                                                     │
│  1 syscall for 5 bytes = ~1000+ nanoseconds                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Writer Types

**1. Fixed Buffer Writer:**

```zig
var buffer: [100]u8 = undefined;
var w: Writer = .fixed(&buffer);

try w.writeAll("Hello");  // Goes into buffer
try w.writeAll("World");  // Goes into buffer
// buffer now contains "HelloWorld"

// If you write more than 100 bytes → error.WriteFailed
```

**2. Allocating Writer (grows as needed):**

```zig
var aw: Writer.Allocating = .init(allocator);
defer aw.deinit();

try aw.writer.writeAll("Hello, ");
try aw.writer.writeAll("World!");
try aw.writer.print("Number: {d}\n", .{42});

// Get the accumulated bytes
const result = aw.writer.buffered();  // "Hello, World!Number: 42\n"
```

How Allocating works:

```
Initial: empty buffer

write("Hello"):
  → Buffer too small
  → Allocate 8 bytes
  → Copy "Hello"
  ┌───┬───┬───┬───┬───┬───┬───┬───┐
  │ H │ e │ l │ l │ o │ ? │ ? │ ? │
  └───┴───┴───┴───┴───┴───┴───┴───┘
                      ↑           ↑
                    end=5     len=8

write(", World!"):
  → Buffer too small (need 13, have 8)
  → Reallocate to 16 bytes
  → Copy ", World!"
  ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
  │ H │ e │ l │ l │ o │ , │   │ W │ o │ r │ l │ d │ ! │ ? │ ? │ ? │
  └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                                                      ↑
                                                   end=13
```

---

## Part 2: Threads

Now let's look at how Zig implements threading.

### What is a Thread?

```
Process (your running program):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Shared Memory                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Global variables    Heap allocations    Code                │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                        ↑           ↑           ↑                    │
│                        │           │           │                    │
│         ┌──────────────┴──┬────────┴───────────┴──────────────┐     │
│         │                 │                                   │     │
│  ┌──────▼──────┐   ┌──────▼──────┐                    ┌───────▼───┐ │
│  │  Thread 1   │   │  Thread 2   │        ...         │  Thread N │ │
│  │ ┌─────────┐ │   │ ┌─────────┐ │                    │┌─────────┐│ │
│  │ │  Stack  │ │   │ │  Stack  │ │                    ││  Stack  ││ │
│  │ │ (local) │ │   │ │ (local) │ │                    ││ (local) ││ │
│  │ └─────────┘ │   │ └─────────┘ │                    │└─────────┘│ │
│  │ ┌─────────┐ │   │ ┌─────────┐ │                    │┌─────────┐│ │
│  │ │Registers│ │   │ │Registers│ │                    ││Registers││ │
│  │ └─────────┘ │   │ └─────────┘ │                    │└─────────┘│ │
│  └─────────────┘   └─────────────┘                    └───────────┘ │
│                                                                     │
│  Each thread has:                  All threads share:               │
│  • Own stack (local variables)     • Global variables               │
│  • Own registers (CPU state)       • Heap memory                    │
│  • Own instruction pointer         • File descriptors               │
│                                    • Code                           │
└─────────────────────────────────────────────────────────────────────┘
```

### Spawning a Thread in Zig

```zig
const std = @import("std");

fn worker(id: usize) void {
    std.debug.print("Worker {d} starting\n", .{id});
    // Do work...
    std.debug.print("Worker {d} done\n", .{id});
}

pub fn main() !void {
    // Spawn a new thread that runs worker(42)
    const thread = try std.Thread.spawn(.{}, worker, .{42});

    // Main thread continues here...
    std.debug.print("Main thread waiting\n", .{});

    // Wait for thread to finish
    thread.join();

    std.debug.print("All done\n", .{});
}
```

**What happens when you call `Thread.spawn()`:**

```
Main Thread                           New Thread
┌──────────────────────┐
│ 1. Call spawn()      │
│    │                 │
│    ▼                 │
│ 2. Allocate stack    │
│    (16MB by default) │
│    │                 │
│    ▼                 │
│ 3. Syscall to create │──────────────► 4. New thread starts
│    new thread        │              │    ┌─────────────────┐
│    │                 │              │    │ Run worker(42)  │
│    ▼                 │              │    │ ...             │
│ 5. Return Thread     │              │    │ Function returns│
│    handle            │              │    └─────────────────┘
│    │                 │              │           │
│    ▼                 │              │           ▼
│ 6. Main continues... │              │    5. Thread exits
│    │                 │
│    ▼                 │
│ 7. thread.join()     │◄─────────────────────────┘
│    (waits for exit)  │
│    │                 │
│    ▼                 │
│ 8. Continue          │
└──────────────────────┘
```

### How Linux Creates Threads: The `clone` Syscall

Zig on Linux uses the `clone` syscall directly (without libc):

```zig
const flags: u32 =
    linux.CLONE.THREAD |       // Share thread group (same process)
    linux.CLONE.VM |           // Share memory space
    linux.CLONE.FS |           // Share filesystem info
    linux.CLONE.FILES |        // Share file descriptors
    linux.CLONE.SIGHAND |      // Share signal handlers
    linux.CLONE.PARENT_SETTID | // Write thread ID to parent
    linux.CLONE.CHILD_CLEARTID; // Clear thread ID when child exits

linux.clone(
    entryFn,           // Function to run in new thread
    stack_pointer,      // Top of new thread's stack
    flags,              // What to share
    arg_pointer,        // Argument to pass
    &parent_tid,        // Where to write parent's view of TID
    tls_pointer,        // Thread-local storage
    &child_tid,         // Where to write child's TID
);
```

**Memory layout for a new thread:**

```
Allocated memory region:
┌────────────────────────────────────────────────────────────────────────┐
│                                                                        │
│  ┌──────────────┬──────────────────────┬─────────────┬───────────────┐ │
│  │  Guard Page  │        Stack         │    TLS      │   Instance    │ │
│  │  (no access) │     (grows down)     │  Segment    │  (args/state) │ │
│  └──────────────┴──────────────────────┴─────────────┴───────────────┘ │
│        ↑                   ↑                  ↑              ↑         │
│   If stack overflows,   Stack pointer      Thread-local    Function    │
│   crash here instead    starts here        variables       arguments   │
│   of corrupting memory                                                 │
│                                                                        │
│  Guard page prevents stack overflow from silently corrupting memory    │
│  TLS = Thread Local Storage (each thread gets own copy)                │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Thread-Local Storage

Sometimes you need each thread to have its own copy of a variable:

```zig
// Normal global: shared by ALL threads (dangerous!)
var shared_counter: u32 = 0;

// Thread-local: each thread has its OWN copy (safe!)
threadlocal var thread_id: ?u32 = null;

fn worker() void {
    // Each thread sets its own thread_id
    thread_id = getCurrentThreadId();

    // This thread_id is independent of other threads!
    std.debug.print("My ID: {d}\n", .{thread_id.?});
}
```

Visual representation:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SHARED MEMORY                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  shared_counter = 42  (ONE copy, all threads see same value)  │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│     Thread 1        │  │     Thread 2        │  │     Thread 3        │
│ ┌─────────────────┐ │  │ ┌─────────────────┐ │  │ ┌─────────────────┐ │
│ │ thread_id = 101 │ │  │ │ thread_id = 102 │ │  │ │ thread_id = 103 │ │
│ │ (own copy)      │ │  │ │ (own copy)      │ │  │ │ (own copy)      │ │
│ └─────────────────┘ │  │ └─────────────────┘ │  │ └─────────────────┘ │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘

Each thread has SEPARATE thread-local storage
Modifications in one thread don't affect others
```

---

## Part 3: Synchronization - Making Threads Cooperate

When multiple threads access shared data, chaos ensues without synchronization.

### The Problem: Race Conditions

```zig
var counter: u32 = 0;

fn increment() void {
    counter += 1;  // DANGER! Not atomic!
}

// Spawn 1000 threads, each calling increment()
// Expected result: counter = 1000
// Actual result: counter = ??? (probably less than 1000)
```

**Why does this happen?**

```
counter += 1 is actually THREE steps:

1. LOAD:  Read counter from memory into register
2. ADD:   Add 1 to register
3. STORE: Write register back to memory

Two threads running "simultaneously":

Thread A                    Thread B                    Memory
─────────────────────────────────────────────────────────────────
                                                        counter = 0

LOAD counter (get 0)                                    counter = 0
                            LOAD counter (get 0)        counter = 0
ADD 1 (register = 1)
                            ADD 1 (register = 1)
STORE counter                                           counter = 1
                            STORE counter               counter = 1

Expected: counter = 2
Actual:   counter = 1       ← LOST UPDATE!

Both threads read 0, both add 1, both write 1
One increment was LOST
```

### The Solution: Mutual Exclusion (Mutex)

A mutex ensures only ONE thread can access protected data at a time:

```zig
var mutex: std.Thread.Mutex = .{};
var counter: u32 = 0;

fn increment() void {
    mutex.lock();           // Wait until we can enter
    defer mutex.unlock();   // Always unlock when we're done

    counter += 1;           // Now this is SAFE!
}
```

**How it works:**

```
Thread A                    Thread B                    Mutex State
─────────────────────────────────────────────────────────────────────
                                                        UNLOCKED

lock() - acquired!                                      LOCKED (by A)
                            lock() - BLOCKED!
                            (waiting...)
LOAD counter (get 0)        (waiting...)
ADD 1 (register = 1)        (waiting...)
STORE counter               (waiting...)                counter = 1
unlock()                                                UNLOCKED
                            lock() - acquired!          LOCKED (by B)
                            LOAD counter (get 1)
                            ADD 1 (register = 2)
                            STORE counter               counter = 2
                            unlock()                    UNLOCKED

Result: counter = 2 ✓
```

### How Mutex Works Internally: The Futex

Zig's Mutex uses a **Futex** (Fast Userspace muTEX) on Linux:

```zig
const FutexImpl = struct {
    state: atomic.Value(u32) = atomic.Value(u32).init(unlocked),

    const unlocked: u32 = 0b00;   // Nobody holds the lock
    const locked: u32 = 0b01;     // Someone holds the lock
    const contended: u32 = 0b11;  // Locked AND others are waiting
```

**State machine:**

```
                         ┌─────────────────┐
                         │    UNLOCKED     │
                         │     (0b00)      │
                         └────────┬────────┘
                                  │
                          lock() by Thread A
                                  │
                                  ▼
                         ┌─────────────────┐
                         │     LOCKED      │ ◄─── Thread A holds lock
                         │     (0b01)      │
                         └────────┬────────┘
                                  │
                          lock() by Thread B
                          (Thread B must wait)
                                  │
                                  ▼
                         ┌─────────────────┐
                         │   CONTENDED     │ ◄─── Thread A holds lock
                         │     (0b11)      │      Thread B is waiting
                         └────────┬────────┘
                                  │
                          unlock() by Thread A
                          (must wake Thread B!)
                                  │
                                  ▼
                         ┌─────────────────┐
                         │    UNLOCKED     │ ◄─── Thread B wakes up
                         │     (0b00)      │      and acquires lock
                         └─────────────────┘
```

**The magic of futex: efficient waiting**

```
Why not just spin (busy-wait)?
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  // Spinning wastes CPU cycles!                                     │
│  while (state != unlocked) {                                        │
│      // Thread B burns CPU doing NOTHING useful                     │
│      // Other threads can't use this CPU core                       │
│      // Your laptop gets hot                                        │
│  }                                                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Futex is smarter:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Thread B calls futex_wait(&state, locked):                         │
│                                                                     │
│  1. Check: is state still 'locked'?                                 │
│  2. If yes: PUT THIS THREAD TO SLEEP                                │
│     - Thread B uses ZERO CPU while sleeping                         │
│     - OS scheduler runs other threads                               │
│                                                                     │
│  Thread A calls futex_wake(&state, 1):                              │
│                                                                     │
│  1. WAKE UP one thread sleeping on &state                           │
│  2. Thread B wakes up and tries to acquire lock                     │
│                                                                     │
│  The check-and-sleep is ATOMIC - no race condition!                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The Lock/Unlock Code

```zig
fn lock(self: *@This()) void {
    // Fast path: try to acquire immediately
    if (self.tryLock()) return;

    // Slow path: we have to wait
    self.lockSlow();
}

fn tryLock(self: *@This()) bool {
    // Atomically: if state == unlocked, set to locked
    return self.state.cmpxchgWeak(
        unlocked,   // Expected value
        locked,     // New value if expected matches
        .acquire,   // Memory ordering
        .monotonic,
    ) == null;     // null means success!
}

fn lockSlow(self: *@This()) void {
    @branchHint(.cold);  // This path is rare

    // Set state to 'contended' and wait
    while (self.state.swap(contended, .acquire) != unlocked) {
        // State is locked/contended - go to sleep
        Futex.wait(&self.state, contended);
        // When we wake up, try again (loop)
    }
}

fn unlock(self: *@This()) void {
    const state = self.state.swap(unlocked, .release);
    assert(state != unlocked);  // Can't unlock if not locked!

    // If there were waiters, wake one up
    if (state == contended) {
        Futex.wake(&self.state, 1);  // Wake one waiter
    }
}
```

### Step-by-Step: Lock Contention

```
Initial state: UNLOCKED

Thread A: lock()
┌─────────────────────────────────────────────────────────────────────┐
│ Step 1: tryLock()                                                   │
│         cmpxchg(unlocked → locked)?  state IS unlocked!             │
│         SUCCESS! Set state = locked, return                         │
└─────────────────────────────────────────────────────────────────────┘
State: LOCKED

Thread B: lock()
┌─────────────────────────────────────────────────────────────────────┐
│ Step 1: tryLock()                                                   │
│         cmpxchg(unlocked → locked)?  state is locked, NOT unlocked  │
│         FAILED! Fall through to lockSlow()                          │
│                                                                     │
│ Step 2: lockSlow()                                                  │
│         swap(contended) returns 'locked' (not unlocked)             │
│         State is now CONTENDED                                      │
│                                                                     │
│ Step 3: Futex.wait(&state, contended)                               │
│         Thread B goes to SLEEP                                      │
│         zzz...                                                      │
└─────────────────────────────────────────────────────────────────────┘
State: CONTENDED, Thread B sleeping

Thread A: unlock()
┌─────────────────────────────────────────────────────────────────────┐
│ Step 1: swap(unlocked) returns 'contended'                          │
│         State is now UNLOCKED                                       │
│                                                                     │
│ Step 2: state WAS contended, so there are waiters                   │
│         Futex.wake(&state, 1) - wake Thread B!                      │
└─────────────────────────────────────────────────────────────────────┘
State: UNLOCKED, Thread B waking up

Thread B: (continues in lockSlow)
┌─────────────────────────────────────────────────────────────────────┐
│ Step 4: Woke up! Loop back to swap()                                │
│         swap(contended) returns 'unlocked'                          │
│         SUCCESS! We acquired the lock!                              │
└─────────────────────────────────────────────────────────────────────┘
State: CONTENDED (Thread B holds lock)
```

---

## Part 4: Other Synchronization Primitives

### RwLock - Multiple Readers OR One Writer

Sometimes you have data that's read often but written rarely:

```zig
var rwlock: std.Thread.RwLock = .{};
var shared_data: Data = .{};

fn readData() Data {
    rwlock.lockShared();        // Multiple readers allowed!
    defer rwlock.unlockShared();
    return shared_data;
}

fn writeData(new_data: Data) void {
    rwlock.lockExclusive();     // Only ONE writer allowed
    defer rwlock.unlockExclusive();
    shared_data = new_data;
}
```

**Visual:**

```
State 1: No locks
┌─────────────────────────────────────────────────────────────────────┐
│                         (available)                                 │
└─────────────────────────────────────────────────────────────────────┘

State 2: Multiple readers (shared locks)
┌─────────────────────────────────────────────────────────────────────┐
│ Reader A │ Reader B │ Reader C │ Reader D │ ... can have many!     │
└─────────────────────────────────────────────────────────────────────┘
Writers BLOCKED - must wait for all readers to finish

State 3: One writer (exclusive lock)
┌─────────────────────────────────────────────────────────────────────┐
│                         Writer X                                    │
└─────────────────────────────────────────────────────────────────────┘
ALL readers and other writers BLOCKED
```

### Condition Variable - Waiting for a Condition

For producer-consumer patterns:

```zig
const Queue = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    items: std.ArrayList(Item),

    fn push(self: *Queue, item: Item) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.items.append(item);
        self.cond.signal();  // Wake up ONE waiting consumer
    }

    fn pop(self: *Queue) Item {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Wait until there's something to pop
        while (self.items.items.len == 0) {
            self.cond.wait(&self.mutex);  // Sleep until signaled
        }

        return self.items.pop();
    }
};
```

**How wait() works:**

```
Thread calls cond.wait(&mutex):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  1. ATOMICALLY:                                                     │
│     • Unlock the mutex                                              │
│     • Add this thread to condition's wait queue                     │
│     • Put thread to sleep                                           │
│                                                                     │
│  2. ... zzz ... (sleeping)                                          │
│                                                                     │
│  3. Another thread calls cond.signal()                              │
│     • This thread wakes up                                          │
│                                                                     │
│  4. ATOMICALLY:                                                     │
│     • Remove from wait queue                                        │
│     • Re-acquire the mutex (may block again!)                       │
│                                                                     │
│  5. Return from wait()                                              │
│     • Mutex is locked again                                         │
│     • Can now safely check/access shared data                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Why the while loop?
• "Spurious wakeups" - thread might wake up for no reason
• Another consumer might have taken the item first
• ALWAYS re-check the condition after waking up!
```

### Semaphore - Counting Access

Limit concurrent access to a resource:

```zig
var semaphore = std.Thread.Semaphore{ .permits = 3 };  // Allow 3 at once

fn accessResource() void {
    semaphore.wait();        // Decrement permits (blocks if 0)
    defer semaphore.post();  // Increment permits

    // Only 3 threads can be here at once!
    doWork();
}
```

**Visual:**

```
Semaphore with 3 permits:

Initial: permits = 3
┌─────────────────────────────────────────────────────────────────────┐
│ [■] [■] [■]  ← 3 permits available                                  │
└─────────────────────────────────────────────────────────────────────┘

Thread A calls wait(): permits = 2
┌─────────────────────────────────────────────────────────────────────┐
│ [□] [■] [■]  ← Thread A took one                                    │
└─────────────────────────────────────────────────────────────────────┘

Thread B calls wait(): permits = 1
┌─────────────────────────────────────────────────────────────────────┐
│ [□] [□] [■]  ← Threads A, B using resource                          │
└─────────────────────────────────────────────────────────────────────┘

Thread C calls wait(): permits = 0
┌─────────────────────────────────────────────────────────────────────┐
│ [□] [□] [□]  ← Threads A, B, C using resource                       │
└─────────────────────────────────────────────────────────────────────┘

Thread D calls wait(): BLOCKED! (permits = 0)
┌─────────────────────────────────────────────────────────────────────┐
│ [□] [□] [□]  Thread D: 💤 waiting...                                │
└─────────────────────────────────────────────────────────────────────┘

Thread A calls post(): permits = 1, Thread D wakes up!
┌─────────────────────────────────────────────────────────────────────┐
│ [□] [□] [□]  ← Now B, C, D using resource                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Atomics - Lock-Free Operations

Sometimes you don't need a full mutex - atomics are faster for simple operations.

### The Problem with Normal Variables

```zig
var counter: u32 = 0;

// Thread A:
counter += 1;  // NOT ATOMIC!

// This compiles to multiple instructions:
// 1. mov eax, [counter]   ; Load
// 2. add eax, 1           ; Add
// 3. mov [counter], eax   ; Store
//
// Another thread can interrupt between ANY of these!
```

### Atomic Operations

```zig
var counter = std.atomic.Value(u32).init(0);

// Thread A:
_ = counter.fetchAdd(1, .monotonic);  // ATOMIC!

// This compiles to ONE atomic instruction:
// lock xadd [counter], 1
//
// The "lock" prefix makes it atomic - cannot be interrupted
```

### Memory Ordering - The Hard Part

Why do we need `.monotonic`, `.acquire`, `.release`?

```
Modern CPUs reorder instructions for performance!

You write:                    CPU might execute:
──────────────────────────────────────────────────────────
store(data, 42);              store(ready, true);  ← REORDERED!
store(ready, true);           store(data, 42);

This is FASTER for the CPU but BREAKS multi-threaded code!

Thread A:                     Thread B:
data = 42;                    if (ready) {
ready = true;                     print(data);  // Might print 0!
                              }

Thread B might see ready=true BEFORE data=42 is visible!
```

**Memory orderings explained:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ .monotonic (weakest)                                                │
│ ─────────────────────                                               │
│ "Just make THIS operation atomic, nothing else"                     │
│                                                                     │
│ Use for: Independent counters, statistics                           │
│ Example: counter.fetchAdd(1, .monotonic);                           │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ .acquire (for loads/reads)                                          │
│ ─────────────────────────                                           │
│ "After I read this, I want to see all writes that happened          │
│  before the matching release"                                       │
│                                                                     │
│ Think: "Acquire the lock - now I can see what others did"           │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ .release (for stores/writes)                                        │
│ ────────────────────────────                                        │
│ "Before this write becomes visible, all my previous writes          │
│  must also be visible"                                              │
│                                                                     │
│ Think: "Release the lock - others can now see my work"              │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ .seq_cst (strongest, slowest)                                       │
│ ────────────────────────────                                        │
│ "Total global ordering - all threads see operations in same order"  │
│                                                                     │
│ Use when unsure - correct but slower                                │
└─────────────────────────────────────────────────────────────────────┘
```

**Example: Safe flag with acquire/release:**

```zig
var data: Data = undefined;
var ready = std.atomic.Value(bool).init(false);

// Thread A (producer):
data = computeData();                    // 1. Write data
ready.store(true, .release);             // 2. Release: "data is ready"

// Thread B (consumer):
while (!ready.load(.acquire)) {}         // 1. Acquire: wait for ready
const d = data;                          // 2. Now safe to read data!
```

**Why this works:**

```
Thread A                          Thread B
────────────────────────────────────────────────────────────────
data = computeData();
        │
        │ .release ensures:
        │ "data write visible BEFORE ready write"
        ▼
ready.store(true, .release);
                                  ready.load(.acquire);
                                          │
                                          │ .acquire ensures:
                                          │ "see all writes before the release"
                                          ▼
                                  const d = data;  // SEES computed data!
```

---

## Part 6: Async IO - io_uring

Traditional IO blocks the thread. io_uring lets you submit many operations and collect results later.

### The Problem with Blocking IO

```
Traditional approach: one thread per connection
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Thread 1: read(conn1) ────────[BLOCKED]──────────► got data        │
│  Thread 2: read(conn2) ────────[BLOCKED]──────────► got data        │
│  Thread 3: read(conn3) ────────[BLOCKED]──────────► got data        │
│  Thread 4: read(conn4) ────────[BLOCKED]──────────► got data        │
│                                                                     │
│  Problems:                                                          │
│  • 10,000 connections = 10,000 threads = 80GB+ stack memory!        │
│  • Context switches between threads are expensive                   │
│  • Threads mostly sleeping, waiting for slow network                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### io_uring: Submit Many, Collect Later

```
io_uring approach: one thread, many operations
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   ┌───────────────────────────────────────────────────────────────┐ │
│   │  SUBMISSION QUEUE (ring buffer in shared memory)              │ │
│   │  ┌─────────┬─────────┬─────────┬─────────┬─────────┐          │ │
│   │  │ read    │ read    │ write   │ accept  │ send    │          │ │
│   │  │ conn1   │ conn2   │ conn3   │ socket  │ conn4   │          │ │
│   │  └─────────┴─────────┴─────────┴─────────┴─────────┘          │ │
│   └───────────────────────────────────────────────────────────────┘ │
│                           │                                         │
│                           │ One syscall: io_uring_enter()           │
│                           │ "Process all these please"              │
│                           ▼                                         │
│   ┌───────────────────────────────────────────────────────────────┐ │
│   │                     KERNEL                                    │ │
│   │    Does all the work in parallel, notifies when done          │ │
│   └───────────────────────────────────────────────────────────────┘ │
│                           │                                         │
│                           ▼                                         │
│   ┌───────────────────────────────────────────────────────────────┐ │
│   │  COMPLETION QUEUE (ring buffer in shared memory)              │ │
│   │  ┌─────────┬─────────┬─────────┐                              │ │
│   │  │ conn1:  │ conn4:  │ socket: │  More completions arrive...  │ │
│   │  │ 256     │ 128     │ newfd   │                              │ │
│   │  │ bytes   │ bytes   │ = 5     │                              │ │
│   │  └─────────┴─────────┴─────────┘                              │ │
│   └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  Benefits:                                                          │
│  • 10,000 connections with ONE thread!                              │
│  • Minimal syscalls (batch submit, batch collect)                   │
│  • Zero-copy possible with registered buffers                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Using io_uring in Zig

```zig
const std = @import("std");
const linux = std.os.linux;

pub fn main() !void {
    // Initialize io_uring with 256 entries
    var ring = try linux.IoUring.init(256, 0);
    defer ring.deinit();

    // Open a file
    const fd = try std.posix.open("data.txt", .{ .ACCMODE = .RDONLY }, 0);
    defer std.posix.close(fd);

    var buffer: [4096]u8 = undefined;

    // STEP 1: Get a submission queue entry
    const sqe = try ring.get_sqe();

    // STEP 2: Prepare a read operation
    sqe.prep_read(fd, &buffer, 0);  // Read at offset 0

    // STEP 3: Submit to kernel (one syscall for potentially many ops)
    _ = try ring.submit();

    // STEP 4: Wait for completion
    const cqe = try ring.copy_cqe();

    // STEP 5: Check result
    if (cqe.res >= 0) {
        std.debug.print("Read {d} bytes: {s}\n", .{
            cqe.res,
            buffer[0..@intCast(cqe.res)],
        });
    } else {
        std.debug.print("Error: {d}\n", .{cqe.res});
    }
}
```

**Step by step:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. ring.get_sqe()                                                   │
│    ─────────────────                                                │
│    Get a pointer to an empty slot in the submission queue           │
│                                                                     │
│    Submission Queue:                                                │
│    ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐                │
│    │used │used │ ▼   │     │     │     │     │     │                │
│    └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘                │
│                  ↑                                                  │
│                 sqe points here                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ 2. sqe.prep_read(fd, &buffer, 0)                                    │
│    ────────────────────────────────                                 │
│    Fill in the SQE with read parameters                             │
│                                                                     │
│    ┌─────────────────────────────────────┐                          │
│    │  SQE (Submission Queue Entry)       │                          │
│    │  opcode: IORING_OP_READ             │                          │
│    │  fd: 3 (file descriptor)            │                          │
│    │  addr: &buffer                      │                          │
│    │  len: 4096                          │                          │
│    │  off: 0 (file offset)               │                          │
│    └─────────────────────────────────────┘                          │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ 3. ring.submit()                                                    │
│    ─────────────────                                                │
│    Tell kernel: "I have new work in the submission queue"           │
│                                                                     │
│    Userspace ──────────────► Kernel                                 │
│    io_uring_enter(fd, 1, 0, 0)                                      │
│                              │                                      │
│                              │ Kernel sees the read request         │
│                              │ Starts reading from disk             │
│                              │ (happens in background)              │
│                              ▼                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ 4. ring.copy_cqe()                                                  │
│    ──────────────────                                               │
│    Wait for and retrieve a completion                               │
│                                                                     │
│    Completion Queue:                                                │
│    ┌─────────────────────────────────────┐                          │
│    │  CQE (Completion Queue Entry)       │                          │
│    │  user_data: (identifies which req)  │                          │
│    │  res: 1234 (bytes read, or error)   │                          │
│    │  flags: 0                           │                          │
│    └─────────────────────────────────────┘                          │
│                                                                     │
│    cqe.res > 0 means success (number of bytes)                      │
│    cqe.res < 0 means error (negative errno)                         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 7: Coroutines, Stackless Functions & Green Threads

Beyond OS threads and raw async IO, there are other execution models. Let's understand them from first principles.

### The Problem: Threads Are Expensive

```
OS Thread Cost:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Each OS thread needs:                                              │
│  • Stack memory: 1-8 MB (default varies by OS)                      │
│  • Kernel data structures: ~10 KB                                   │
│  • Context switch cost: 1-10 microseconds                           │
│                                                                     │
│  10,000 connections with thread-per-connection:                     │
│  • Memory: 10,000 × 8 MB = 80 GB just for stacks!                   │
│  • Kernel objects: 100 MB                                           │
│  • Context switches: thousands per second                           │
│                                                                     │
│  This doesn't scale.                                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Solution 1: Green Threads (Stackful Coroutines)

**The idea**: Create our own "lightweight threads" in userspace.

```
Green Threads (like Go goroutines, Erlang processes):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  One OS Thread can run MANY green threads                           │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                     OS Thread                                │    │
│  │  ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐          │    │
│  │  │Green 1│ │Green 2│ │Green 3│ │Green 4│ │Green 5│ ...      │    │
│  │  │2KB stk│ │2KB stk│ │2KB stk│ │2KB stk│ │2KB stk│          │    │
│  │  └───────┘ └───────┘ └───────┘ └───────┘ └───────┘          │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  Benefits:                                                          │
│  • Tiny stacks (2-8 KB instead of 1-8 MB)                           │
│  • Cheap switching (no syscall, ~100 nanoseconds)                   │
│  • Can have millions of green threads                               │
│                                                                     │
│  How they work:                                                     │
│  • Each green thread has its OWN small stack                        │
│  • Runtime scheduler switches between them                          │
│  • On blocking operation: save stack pointer, switch to another     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Why "stackful"?**

Each green thread has its own stack that persists across yield points:

```
Green Thread A's Stack:            Green Thread B's Stack:
┌─────────────────────┐           ┌─────────────────────┐
│ main()              │           │ main()              │
│   └─► process()     │           │   └─► handle()      │
│         └─► parse() │           │         └─► read()  │
│              │      │           │              │      │
│              ▼      │           │              ▼      │
│         [YIELDED]   │           │           [RUNNING] │
└─────────────────────┘           └─────────────────────┘

When Green Thread A yields:
1. Save stack pointer (just one register!)
2. Switch to Green Thread B's stack pointer
3. Continue running B

The ENTIRE call stack is preserved!
Can yield from ANY depth in the call tree.
```

**Go's goroutines example:**

```go
// Go - stackful goroutines
func handler(conn net.Conn) {
    for {
        data := conn.Read()   // Yields here if no data
        process(data)         // Full stack preserved
        conn.Write(response)  // Yields here if buffer full
    }
}

func main() {
    for {
        conn := listener.Accept()
        go handler(conn)  // Spawns lightweight goroutine
    }
}
// Can have 1 million goroutines!
```

**The cost of stackful:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ Stackful Coroutine Tradeoffs:                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ✓ Natural code flow (looks like regular functions)                  │
│ ✓ Can yield from any call depth                                     │
│ ✓ Easy to reason about                                              │
│                                                                     │
│ ✗ Still needs stack per coroutine (2-8 KB each)                     │
│ ✗ Stack size hard to predict (may need to grow)                     │
│ ✗ Stack switching needs careful implementation                      │
│ ✗ Harder to optimize - compiler can't see across yields             │
│                                                                     │
│ 1 million goroutines × 2 KB = 2 GB just for stacks                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### Solution 2: Stackless Coroutines (Async/Await)

**The idea**: Don't give each coroutine a stack. Instead, transform the function into a state machine.

```
Stackless Coroutine (like Rust async, JavaScript async):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  No separate stack! Just a STATE MACHINE struct.                    │
│                                                                     │
│  async fn fetch_data() {          Compiles to:                      │
│      let x = read().await;        ┌──────────────────────┐          │
│      let y = process(x);    ───►  │ struct FetchData {   │          │
│      write(y).await;              │   state: u8,         │          │
│  }                                │   x: Option<Data>,   │          │
│                                   │   y: Option<Data>,   │          │
│                                   │ }                    │          │
│                                   └──────────────────────┘          │
│                                                                     │
│  The struct holds ONLY what needs to live across await points       │
│  No stack! Just a small struct in memory.                           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**How the transformation works:**

```
Original async function:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  async fn example() -> i32 {                                        │
│      let a = fetch().await;    // Yield point 1                     │
│      let b = a + 1;                                                 │
│      let c = save(b).await;    // Yield point 2                     │
│      return c * 2;                                                  │
│  }                                                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Transformed into state machine:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  struct ExampleStateMachine {                                       │
│      state: enum { Start, AfterFetch, AfterSave, Done },            │
│      a: Option<i32>,                                                │
│      b: Option<i32>,                                                │
│      c: Option<i32>,                                                │
│      fetch_future: Option<FetchFuture>,                             │
│      save_future: Option<SaveFuture>,                               │
│  }                                                                  │
│                                                                     │
│  impl Future for ExampleStateMachine {                              │
│      fn poll(&mut self) -> Poll<i32> {                              │
│          loop {                                                     │
│              match self.state {                                     │
│                  Start => {                                         │
│                      self.fetch_future = Some(fetch());             │
│                      self.state = AfterFetch;                       │
│                  }                                                  │
│                  AfterFetch => {                                    │
│                      match self.fetch_future.poll() {               │
│                          Ready(a) => {                              │
│                              self.a = Some(a);                      │
│                              self.b = Some(a + 1);                  │
│                              self.save_future = Some(save(self.b)); │
│                              self.state = AfterSave;                │
│                          }                                          │
│                          Pending => return Pending,                 │
│                      }                                              │
│                  }                                                  │
│                  AfterSave => {                                     │
│                      match self.save_future.poll() {                │
│                          Ready(c) => {                              │
│                              self.c = Some(c);                      │
│                              self.state = Done;                     │
│                              return Ready(c * 2);                   │
│                          }                                          │
│                          Pending => return Pending,                 │
│                      }                                              │
│                  }                                                  │
│              }                                                      │
│          }                                                          │
│      }                                                              │
│  }                                                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Visual comparison:**

```
STACKFUL (Green Thread):              STACKLESS (State Machine):
┌─────────────────────────┐           ┌─────────────────────────┐
│                         │           │                         │
│  ┌───────────────────┐  │           │  ┌───────────────────┐  │
│  │  Actual Stack     │  │           │  │ Struct (32 bytes) │  │
│  │  2048 bytes       │  │           │  │  state: AfterFetch│  │
│  │  ┌─────────────┐  │  │           │  │  a: Some(42)      │  │
│  │  │ return addr │  │  │           │  │  b: None          │  │
│  │  │ local vars  │  │  │           │  │  ...              │  │
│  │  │ saved regs  │  │  │           │  └───────────────────┘  │
│  │  │ ...         │  │  │           │                         │
│  │  │ ...         │  │  │           │  No stack!              │
│  │  │ ...         │  │  │           │  Size known at compile  │
│  │  └─────────────┘  │  │           │  time.                  │
│  └───────────────────┘  │           │                         │
│                         │           │                         │
│  Fixed 2KB per task     │           │  Only 32 bytes for this │
│                         │           │  task's state           │
└─────────────────────────┘           └─────────────────────────┘

1 million tasks:
• Stackful: 2 GB minimum
• Stackless: 32 MB (size varies per task)
```

**Stackless tradeoffs:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ Stackless Coroutine Tradeoffs:                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ✓ Minimal memory per coroutine (just the state struct)              │
│ ✓ Size known at compile time - no runtime stack growth              │
│ ✓ Can be heavily optimized (compiler sees everything)               │
│ ✓ Can inline across await points                                    │
│                                                                     │
│ ✗ "Function coloring" - async infects everything                    │
│ ✗ Can only await at explicit points (not from deep calls)           │
│ ✗ More complex to implement in the compiler                         │
│ ✗ Harder to debug (state machine vs natural stack)                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### The "Function Coloring" Problem

```
Stackless async creates TWO kinds of functions:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  "Red" functions (async):        "Blue" functions (sync):           │
│  ┌───────────────────────┐      ┌───────────────────────┐          │
│  │ async fn fetch() {}   │      │ fn compute() {}       │          │
│  │ async fn process() {} │      │ fn validate() {}      │          │
│  │ async fn handle() {}  │      │ fn format() {}        │          │
│  └───────────────────────┘      └───────────────────────┘          │
│                                                                     │
│  RULES:                                                             │
│  • Async can call sync ✓                                            │
│  • Async can call async ✓ (with await)                              │
│  • Sync can call sync ✓                                             │
│  • Sync can call async ✗ (CANNOT await in sync function!)           │
│                                                                     │
│  Problem: If a deep helper needs to become async, you must          │
│  change EVERY function in the call chain!                           │
│                                                                     │
│  fn main() {                  async fn main() {                     │
│      process();          →        process().await;                  │
│  }                            }                                     │
│                                                                     │
│  fn process() {               async fn process() {                  │
│      fetch();            →        fetch().await;                    │
│  }                            }                                     │
│                                                                     │
│  fn fetch() {                 async fn fetch() {                    │
│      // became async     →        network_call().await;             │
│  }                            }                                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Stackful doesn't have this problem:**

```go
// Go - no function coloring!
func main() {
    process()  // Just call it normally
}

func process() {
    fetch()    // Just call it normally
}

func fetch() {
    // This blocks, but runtime handles it
    // No change needed in callers!
    net.Dial("tcp", "example.com:80")
}
```

---

### Zig's Approach: No Built-in Async (Currently)

Zig had async/await in earlier versions but **removed it** before 1.0. Why?

```
Zig's Async History:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│ Zig 0.5-0.10: Had built-in async/await (stackless)                  │
│                                                                     │
│   const frame = async myAsyncFn();  // Start coroutine              │
│   // ... do other work ...                                          │
│   const result = await frame;       // Get result                   │
│                                                                     │
│ Zig 0.11+: REMOVED async, focusing on other priorities              │
│                                                                     │
│ Current approach in Zig 0.15:                                       │
│ • Use io_uring for async IO (Linux)                                 │
│ • Use epoll/kqueue for event loops                                  │
│ • Manual state machines if needed                                   │
│ • Thread pools for parallelism                                      │
│                                                                     │
│ Future: Async may return, but with different design                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Manual state machine in Zig:**

```zig
const State = enum {
    init,
    reading,
    processing,
    writing,
    done,
};

const Task = struct {
    state: State = .init,
    buffer: [4096]u8 = undefined,
    bytes_read: usize = 0,
    result: ?[]u8 = null,

    fn step(self: *Task, ring: *IoUring) !bool {
        switch (self.state) {
            .init => {
                // Submit read request
                const sqe = try ring.get_sqe();
                sqe.prep_read(self.fd, &self.buffer, 0);
                self.state = .reading;
                return false;  // Not done yet
            },
            .reading => {
                // Check if read completed (called when CQE arrives)
                self.state = .processing;
                return false;
            },
            .processing => {
                // Do sync processing
                self.result = process(self.buffer[0..self.bytes_read]);
                self.state = .writing;
                return false;
            },
            .writing => {
                // Submit write request
                const sqe = try ring.get_sqe();
                sqe.prep_write(self.fd, self.result.?, 0);
                self.state = .done;
                return false;
            },
            .done => {
                return true;  // Task complete!
            },
        }
    }
};
```

---

### Comparison: All Execution Models

```
┌────────────────┬────────────────┬────────────────┬────────────────┐
│                │   OS Threads   │ Green Threads  │   Stackless    │
│                │                │  (Stackful)    │   Async/Await  │
├────────────────┼────────────────┼────────────────┼────────────────┤
│ Stack per task │   1-8 MB       │   2-8 KB       │   0 (struct)   │
├────────────────┼────────────────┼────────────────┼────────────────┤
│ Context switch │   1-10 µs      │   ~100 ns      │   ~10 ns       │
│                │   (syscall)    │   (userspace)  │   (just call)  │
├────────────────┼────────────────┼────────────────┼────────────────┤
│ Max tasks      │   ~10,000      │   ~1,000,000   │   ~10,000,000  │
├────────────────┼────────────────┼────────────────┼────────────────┤
│ Parallelism    │   ✓ Real       │   Depends*     │   Need threads │
├────────────────┼────────────────┼────────────────┼────────────────┤
│ Yield from     │   Anywhere     │   Anywhere     │   Only await   │
│ nested calls   │                │                │   points       │
├────────────────┼────────────────┼────────────────┼────────────────┤
│ Function       │   None         │   None         │   Yes (async   │
│ coloring       │                │                │   vs sync)     │
├────────────────┼────────────────┼────────────────┼────────────────┤
│ Debugging      │   Easy         │   Medium       │   Hard         │
│                │   (real stack) │                │   (state mach) │
├────────────────┼────────────────┼────────────────┼────────────────┤
│ Examples       │   pthreads,    │   Go, Erlang,  │   Rust, JS,    │
│                │   Zig Thread   │   Lua, early   │   C#, Python   │
│                │                │   Zig async    │   asyncio      │
└────────────────┴────────────────┴────────────────┴────────────────┘

* Go multiplexes goroutines across OS threads for true parallelism
```

---

### How Go Does It: M:N Threading

```
Go's Runtime Model:
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  G = Goroutine (green thread, 2KB stack)                            │
│  M = Machine (OS thread)                                            │
│  P = Processor (scheduler context, usually = CPU cores)             │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Global Run Queue                          │    │
│  │    [G] [G] [G] [G] [G] [G] ... (waiting goroutines)         │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                      │
│         ┌────────────────────┼────────────────────┐                 │
│         │                    │                    │                 │
│         ▼                    ▼                    ▼                 │
│  ┌────────────┐       ┌────────────┐       ┌────────────┐          │
│  │     P0     │       │     P1     │       │     P2     │          │
│  │ Local: [G] │       │ Local: [G] │       │ Local: [G] │          │
│  │        [G] │       │        [G] │       │            │          │
│  └──────┬─────┘       └──────┬─────┘       └──────┬─────┘          │
│         │                    │                    │                 │
│         ▼                    ▼                    ▼                 │
│  ┌────────────┐       ┌────────────┐       ┌────────────┐          │
│  │     M0     │       │     M1     │       │     M2     │          │
│  │ (OS Thread)│       │ (OS Thread)│       │ (OS Thread)│          │
│  │ Running: G │       │ Running: G │       │ Running: G │          │
│  └────────────┘       └────────────┘       └────────────┘          │
│                                                                     │
│  • Many G's (millions possible)                                     │
│  • Few M's (usually = CPU cores)                                    │
│  • P schedules G's onto M's                                         │
│  • If G blocks (syscall), M detaches and P gets new M               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**What happens when a goroutine blocks:**

```
Goroutine G1 makes blocking syscall (e.g., file read):
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│ BEFORE:                        AFTER:                               │
│                                                                     │
│ ┌──────┐                       ┌──────┐                             │
│ │  P0  │──► M0 ──► G1          │  P0  │──► M2 ──► G2                │
│ │      │    (running)          │      │    (running)                │
│ │ [G2] │                       │      │                             │
│ │ [G3] │                       │ [G3] │                             │
│ └──────┘                       └──────┘                             │
│                                                                     │
│                                M0 ──► G1 (blocked in syscall)       │
│                                       ↑                             │
│                                       Still exists, waiting         │
│                                                                     │
│ 1. G1 is about to block                                             │
│ 2. Runtime detaches P0 from M0                                      │
│ 3. Runtime attaches P0 to new M2                                    │
│ 4. M2 runs G2 while M0+G1 wait                                      │
│ 5. When syscall completes, G1 goes back to run queue                │
│                                                                     │
│ Result: Blocking syscall doesn't block other goroutines!            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### When to Use Each Model

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CHOOSING AN EXECUTION MODEL                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  How many concurrent tasks?                                         │
│         │                                                           │
│         ├──► < 100 tasks                                            │
│         │         │                                                 │
│         │         └──► OS Threads are fine                          │
│         │              Simple, debuggable, real parallelism         │
│         │                                                           │
│         ├──► 100 - 10,000 tasks                                     │
│         │         │                                                 │
│         │         └──► Thread Pool + Event Loop                     │
│         │              (epoll/io_uring + worker threads)            │
│         │                                                           │
│         ├──► 10,000 - 1,000,000 tasks                               │
│         │         │                                                 │
│         │         └──► Green Threads (Go, Erlang)                   │
│         │              OR Async/Await (Rust, JS)                    │
│         │                                                           │
│         └──► > 1,000,000 tasks                                      │
│                   │                                                 │
│                   └──► Stackless Async (minimal memory)             │
│                        OR Actor Model (Erlang, Elixir)              │
│                                                                     │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│  Other considerations:                                              │
│                                                                     │
│  • Need to call blocking C libraries?                               │
│    → OS Threads (or Go with CGO overhead)                           │
│                                                                     │
│  • Tight memory constraints (embedded)?                             │
│    → Stackless async or manual state machines                       │
│                                                                     │
│  • Team familiarity?                                                │
│    → Go for green threads, Rust for async/await                     │
│                                                                     │
│  • Debugging important?                                             │
│    → OS Threads (real stack traces)                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Summary: When to Use What

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DECISION FLOWCHART                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  What are you doing?                                                │
│         │                                                           │
│         ├──► CPU-bound work (computation)                           │
│         │         │                                                 │
│         │         └──► Use THREADS with THREAD POOL                 │
│         │              • Image processing                           │
│         │              • Compression                                │
│         │              • Number crunching                           │
│         │                                                           │
│         ├──► IO-bound work (waiting for network/disk)               │
│         │         │                                                 │
│         │         └──► Use ASYNC IO (io_uring, epoll)               │
│         │              • Web servers                                │
│         │              • Database servers                           │
│         │              • File servers                               │
│         │                                                           │
│         └──► Shared state between threads?                          │
│                   │                                                 │
│                   ├──► Simple counter/flag                          │
│                   │         └──► Use ATOMICS                        │
│                   │                                                 │
│                   ├──► Read-heavy, rare writes                      │
│                   │         └──► Use RWLOCK                         │
│                   │                                                 │
│                   ├──► Producer-consumer                            │
│                   │         └──► Use MUTEX + CONDITION              │
│                   │                                                 │
│                   └──► Everything else                              │
│                             └──► Use MUTEX                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Quick Reference: Primitives

| Primitive | Purpose | When to Use |
|-----------|---------|-------------|
| `Thread.spawn()` | Create new thread | Parallel computation |
| `Mutex` | Exclusive access | Protecting shared data |
| `RwLock` | Many readers OR one writer | Read-heavy workloads |
| `Condition` | Wait for event | Producer-consumer |
| `Semaphore` | Limit concurrent access | Connection pools |
| `atomic.Value` | Lock-free operations | Counters, flags |
| `io_uring` | Async IO | High-performance servers |

### Quick Reference: Execution Models

| Model | Stack per Task | Max Tasks | Best For |
|-------|---------------|-----------|----------|
| OS Threads | 1-8 MB | ~10K | CPU-bound parallelism |
| Green Threads (Go) | 2-8 KB | ~1M | Many IO-bound tasks |
| Stackless Async (Rust) | ~bytes | ~10M | Memory-constrained |
| Thread Pool + epoll | Shared | ~100K | Zig approach |

### Memory Ordering Quick Reference

| Ordering | Use For |
|----------|---------|
| `.monotonic` | Independent counters |
| `.acquire` | Reading "ready" flags |
| `.release` | Setting "ready" flags |
| `.acq_rel` | Read-modify-write on shared data |
| `.seq_cst` | When unsure (safest but slowest) |
