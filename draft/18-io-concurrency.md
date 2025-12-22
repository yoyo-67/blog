---
title: "Part 18: IO, Concurrency & Async - Zig 0.16's New Io Interface"
date: 2024-01-15
series: ["Zig Internals"]
series_order: 18
tags: ["zig", "io", "concurrency", "async", "threads", "io_uring", "kqueue"]
---

This article explores Zig 0.16's redesigned IO system, the new async primitives, and how the `Io` interface unifies everything. Zig 0.16 brings async back - not as language keywords, but as library functions that work across different execution models.

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
│  │ BOTH waiting AND computing?           → Use ZIG'S Io        │    │
│  │                                         (unified interface) │    │
│  │                                                             │    │
│  │ Zig 0.16's Io interface handles both!                       │    │
│  │ • Same code works with threads, io_uring, or kqueue         │    │
│  │ • Switch implementations without changing your code         │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: The Io Interface - Zig 0.16's Big Change

Zig 0.16 introduces the `Io` interface - a runtime-polymorphic abstraction that you pass around like `Allocator`. This is **the** fundamental change.

### The Pattern: Io Follows Allocator

```zig
// Just like Allocator, Io is passed to functions that need it
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the Io implementation
    var threaded = try std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Pass both to your application
    try runServer(allocator, io);
}

fn runServer(allocator: Allocator, io: Io) !void {
    // Use io for all I/O operations
    // Use allocator for memory
}
```

### The Io Struct

```
┌─────────────────────────────────────────────────────────────────────┐
│                         std.Io                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   const Io = struct {                                               │
│       vtable: *const VTable,    // How to do operations             │
│       userdata: ?*anyopaque,    // Implementation-specific data     │
│   };                                                                │
│                                                                     │
│   The VTable contains function pointers for:                        │
│   • async()     - Start async operation                             │
│   • concurrent() - Start concurrent operation                       │
│   • await()     - Wait for Future                                   │
│   • cancel()    - Cancel Future                                     │
│   • groupAsync() - Group operations                                 │
│   • sleep()     - Async sleep                                       │
│   • ... and more                                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Why This Design?

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SAME CODE, DIFFERENT BACKENDS                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Your Application Code                                             │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  fn fetchData(io: Io, url: []const u8) ![]u8 {              │   │
│   │      var future = Io.async(io, httpGet, .{io, url});        │   │
│   │      return future.await(io);                               │   │
│   │  }                                                          │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│              ┌───────────────┼───────────────┐                      │
│              ▼               ▼               ▼                      │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│   │   Threaded   │  │   IoUring    │  │    Kqueue    │             │
│   │  (portable)  │  │  (Linux)     │  │  (macOS/BSD) │             │
│   └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                     │
│   BENEFITS:                                                         │
│   • Write once, run optimally everywhere                            │
│   • Test with Threaded, deploy with io_uring                        │
│   • No function coloring (async doesn't infect your API)            │
│   • Cancellation works uniformly                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: The New Reader & Writer

The Reader and Writer in 0.16 keep the same core design (VTable + buffer) but are now integrated with the Io interface.

### Reader Structure

From `std/Io/Reader.zig`:

```zig
const Reader = @This();

vtable: *const VTable,
buffer: []u8,           // The actual bytes we've buffered
seek: usize,            // Where we are in the buffer (consumed)
end: usize,             // Where valid data ends in buffer
```

Visual representation:

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
```

### Writer Structure

From `std/Io/Writer.zig`:

```zig
const Writer = @This();

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

### The VTable Pattern (Unchanged from 0.15)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    BUFFERED + VTABLE DESIGN                         │
├─────────────────────────────────────────────────────────────────────┤
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

---

## Part 3: Async Primitives - The Heart of Zig 0.16

This is the big new feature. Zig 0.16 brings async back - not as keywords, but as library functions.

### Core API: Io.async and Future

```zig
// Launch an async operation
var future = Io.async(io, myFunction, .{arg1, arg2});

// Wait for the result
const result = future.await(io);

// Or cancel (also returns the result)
const result = future.cancel(io);
```

### The Future Type

From `std/Io.zig` line 984:

```zig
pub fn Future(Result: type) type {
    return struct {
        any_future: ?*AnyFuture,
        result: Result,

        /// Wait for completion, get result
        pub fn await(f: *@This(), io: Io) Result {
            const any_future = f.any_future orelse return f.result;
            io.vtable.await(io.userdata, any_future, ...);
            f.any_future = null;
            return f.result;
        }

        /// Cancel and get result
        pub fn cancel(f: *@This(), io: Io) Result {
            const any_future = f.any_future orelse return f.result;
            io.vtable.cancel(io.userdata, any_future, ...);
            f.any_future = null;
            return f.result;
        }
    };
}
```

### Visual: Future Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FUTURE LIFECYCLE                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   1. CREATE                                                         │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  var future = Io.async(io, saveFile, .{data, "file.txt"});  │   │
│   └─────────────────────────────────────────────────────────────┘   │
│        │                                                            │
│        ▼                                                            │
│   ┌──────────────────────────┐                                      │
│   │  Future                  │                                      │
│   │  ├─ any_future: *ptr     │ ◄── Points to internal state        │
│   │  └─ result: undefined    │                                      │
│   └──────────────────────────┘                                      │
│        │                                                            │
│        │  (operation runs in background)                            │
│        │                                                            │
│   2. AWAIT or CANCEL                                                │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │  const result = future.await(io);  // blocks until done     │   │
│   │  // OR                                                      │   │
│   │  const result = future.cancel(io); // request cancel + wait │   │
│   └─────────────────────────────────────────────────────────────┘   │
│        │                                                            │
│        ▼                                                            │
│   ┌──────────────────────────┐                                      │
│   │  Future                  │                                      │
│   │  ├─ any_future: null     │ ◄── Consumed                        │
│   │  └─ result: actual_value │ ◄── Now contains the result         │
│   └──────────────────────────┘                                      │
│                                                                     │
│   NOTE: Both await and cancel are IDEMPOTENT                        │
│         (safe to call multiple times)                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### async vs concurrent: The Critical Difference

```
┌─────────────────────────────────────────────────────────────────────┐
│               Io.async() vs Io.concurrent()                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Io.async(io, func, args)                                          │
│   ────────────────────────                                          │
│   • May run SYNCHRONOUSLY (immediately, blocking)                   │
│   • May run in PARALLEL (on another thread)                         │
│   • NEVER fails - always succeeds                                   │
│   • Works with ALL Io implementations                               │
│   • Decouples calling from returning                                │
│                                                                     │
│   Use when: You don't care HOW it runs, just that it runs           │
│                                                                     │
│   ───────────────────────────────────────────────────────────────   │
│                                                                     │
│   Io.concurrent(io, func, args)                                     │
│   ─────────────────────────────                                     │
│   • MUST run concurrently (on another thread/fiber)                 │
│   • CAN FAIL with error.ConcurrencyUnavailable                      │
│   • Requires Io implementation that supports concurrency            │
│   • Guarantees true parallelism                                     │
│                                                                     │
│   Use when: You NEED parallel execution                             │
│                                                                     │
│   ───────────────────────────────────────────────────────────────   │
│                                                                     │
│   EXAMPLE:                                                          │
│                                                                     │
│   // async: might run now, might run later                          │
│   var f1 = Io.async(io, downloadFile, .{url1});                     │
│   var f2 = Io.async(io, downloadFile, .{url2});                     │
│   // f1 and f2 might overlap, or might run sequentially             │
│                                                                     │
│   // concurrent: MUST run in parallel, or fail                      │
│   var f1 = try Io.concurrent(io, downloadFile, .{url1});            │
│   var f2 = try Io.concurrent(io, downloadFile, .{url2});            │
│   // f1 and f2 are GUARANTEED to be running in parallel             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Group: Managing Multiple Async Operations

```zig
var group: Io.Group = .init;

// Launch multiple tasks
group.async(io, processChunk, .{chunk1});
group.async(io, processChunk, .{chunk2});
group.async(io, processChunk, .{chunk3});

// Wait for all to complete
group.wait(io);

// Or cancel all
// group.cancel(io);
```

Visual:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Io.Group                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   group.async()    group.async()    group.async()                   │
│        │                │                │                          │
│        ▼                ▼                ▼                          │
│   ┌─────────┐      ┌─────────┐      ┌─────────┐                     │
│   │  Task 1 │      │  Task 2 │      │  Task 3 │                     │
│   │ running │      │ running │      │ running │                     │
│   └────┬────┘      └────┬────┘      └────┬────┘                     │
│        │                │                │                          │
│        └────────────────┼────────────────┘                          │
│                         ▼                                           │
│                  group.wait(io)                                     │
│                         │                                           │
│                         ▼                                           │
│                  All completed!                                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Select: Waiting for the First of Multiple Futures

```zig
// Wait for whichever completes first
const result = try Io.select(io, .{
    .file = &file_future,
    .network = &network_future,
    .timer = &timer_future,
});

switch (result) {
    .file => |data| handleFile(data),
    .network => |packet| handlePacket(packet),
    .timer => handleTimeout(),
}
```

---

## Part 4: Io Implementations

Zig 0.16 provides three Io implementations. You choose based on your platform and needs.

### Implementation Comparison

```
┌─────────────────────────────────────────────────────────────────────┐
│                    IO IMPLEMENTATIONS                               │
├─────────────────┬─────────────────┬─────────────────┬───────────────┤
│                 │   Threaded      │   IoUring       │   Kqueue      │
├─────────────────┼─────────────────┼─────────────────┼───────────────┤
│ Platform        │ All             │ Linux only      │ macOS/BSD     │
├─────────────────┼─────────────────┼─────────────────┼───────────────┤
│ File Size       │ 274 KB          │ 53 KB           │ 62 KB         │
├─────────────────┼─────────────────┼─────────────────┼───────────────┤
│ Mechanism       │ Thread pool     │ io_uring        │ kqueue        │
├─────────────────┼─────────────────┼─────────────────┼───────────────┤
│ Syscall per op  │ Many            │ Batched         │ Batched       │
├─────────────────┼─────────────────┼─────────────────┼───────────────┤
│ Best for        │ Portability     │ Linux servers   │ macOS apps    │
├─────────────────┼─────────────────┼─────────────────┼───────────────┤
│ Status          │ Working now     │ Proof of concept│ Proof of concept│
└─────────────────┴─────────────────┴─────────────────┴───────────────┘
```

### Io.Threaded - The Portable Implementation

From `std/Io/Threaded.zig`:

```zig
pub const Threaded = struct {
    allocator: Allocator,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    run_queue: std.SinglyLinkedList = .{},

    /// Max threads for async tasks (defaults to CPU cores)
    async_limit: Io.Limit,

    /// Max threads for concurrent tasks
    concurrent_limit: Io.Limit = .unlimited,

    /// Number of busy threads
    busy_count: usize = 0,

    // ...
};
```

Visual:

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Io.Threaded                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                      Run Queue                               │   │
│   │   [Task] → [Task] → [Task] → [Task] → null                  │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                              ↑                                      │
│                              │                                      │
│   ┌──────────────────────────┼──────────────────────────┐          │
│   │                          │                          │          │
│   ▼                          ▼                          ▼          │
│ ┌────────┐              ┌────────┐              ┌────────┐         │
│ │Thread 1│              │Thread 2│              │Thread 3│         │
│ │ busy   │              │ idle   │              │ busy   │         │
│ └────────┘              └────────┘              └────────┘         │
│                                                                     │
│   async_limit = 4 (max threads)                                     │
│   busy_count = 2 (currently working)                                │
│                                                                     │
│   When Io.async() is called:                                        │
│   1. If idle thread exists → assign task                            │
│   2. If < async_limit → spawn new thread                            │
│   3. Else → run task synchronously                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Usage Example

```zig
const std = @import("std");
const Io = std.Io;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Threaded Io
    var threaded = try Io.Threaded.init(allocator, .{});
    defer threaded.deinit();

    const io = threaded.io();

    // Now use io for async operations
    var future1 = Io.async(io, doWork, .{1});
    var future2 = Io.async(io, doWork, .{2});

    // These might run in parallel on different threads
    const result1 = future1.await(io);
    const result2 = future2.await(io);

    std.debug.print("Results: {}, {}\n", .{result1, result2});
}

fn doWork(n: i32) i32 {
    // Simulate work
    std.time.sleep(100 * std.time.ns_per_ms);
    return n * 10;
}
```

---

## Part 5: Async-Aware Synchronization

Zig 0.16 provides synchronization primitives that work with the Io interface.

### Io.Mutex

```zig
pub const Mutex = struct {
    state: State = .unlocked,

    pub const State = enum(usize) {
        unlocked = 0,
        locked = 1,
        contended = 2,
    };

    pub const init: Mutex = .{ .state = .unlocked };

    pub fn lock(m: *Mutex, io: Io) void { ... }
    pub fn unlock(m: *Mutex) void { ... }
};
```

### Io.Condition

```zig
pub const Condition = struct {
    // For waiting on conditions with the Io interface

    pub const Wake = enum {
        one,
        all,
    };

    pub fn wait(c: *Condition, io: Io, mutex: *Mutex) void { ... }
    pub fn signal(c: *Condition, wake: Wake) void { ... }
};
```

### Example: Producer-Consumer

```zig
var mutex: Io.Mutex = .init;
var cond: Io.Condition = .{};
var queue: Queue = .{};

fn producer(io: Io) void {
    while (true) {
        const item = produceItem();

        mutex.lock(io);
        defer mutex.unlock();

        queue.push(item);
        cond.signal(.one);
    }
}

fn consumer(io: Io) void {
    while (true) {
        mutex.lock(io);
        defer mutex.unlock();

        while (queue.isEmpty()) {
            cond.wait(io, &mutex);
        }

        const item = queue.pop();
        processItem(item);
    }
}
```

---

## Part 6: Putting It All Together

### Complete Example: Parallel File Processing

```zig
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded = try Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const files = [_][]const u8{ "a.txt", "b.txt", "c.txt", "d.txt" };

    // Process all files in parallel
    var group: Io.Group = .init;
    for (files) |file| {
        group.async(io, processFile, .{allocator, file});
    }
    group.wait(io);

    std.debug.print("All files processed!\n", .{});
}

fn processFile(allocator: Allocator, path: []const u8) void {
    // Read, transform, and write the file
    const data = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch return;
    defer allocator.free(data);

    const transformed = transform(data);

    const out_path = std.fmt.allocPrint(allocator, "{s}.out", .{path}) catch return;
    defer allocator.free(out_path);

    std.fs.cwd().writeFile(out_path, transformed) catch return;
}

fn transform(data: []const u8) []const u8 {
    // Your transformation logic
    return data;
}
```

---

## Summary: When to Use What

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DECISION FLOWCHART                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  What are you building?                                             │
│         │                                                           │
│         ├──► Need portable code?                                    │
│         │         └──► Use Io.Threaded                              │
│         │                                                           │
│         ├──► High-performance Linux server?                         │
│         │         └──► Use Io.IoUring                               │
│         │                                                           │
│         └──► macOS/BSD application?                                 │
│                   └──► Use Io.Kqueue                                │
│                                                                     │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│  How to launch async work?                                          │
│         │                                                           │
│         ├──► Don't care about parallelism?                          │
│         │         └──► Io.async() - always works                    │
│         │                                                           │
│         ├──► NEED true parallelism?                                 │
│         │         └──► Io.concurrent() - may fail                   │
│         │                                                           │
│         ├──► Multiple related tasks?                                │
│         │         └──► Io.Group                                     │
│         │                                                           │
│         └──► Wait for first of many?                                │
│                   └──► Io.select()                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Quick Reference

| API | Purpose | Returns |
|-----|---------|---------|
| `Io.async(io, fn, args)` | Start async operation | `Future(Result)` |
| `Io.concurrent(io, fn, args)` | Start parallel operation | `!Future(Result)` |
| `future.await(io)` | Wait for completion | `Result` |
| `future.cancel(io)` | Cancel and get result | `Result` |
| `Io.Group` | Manage multiple tasks | - |
| `Io.select(io, futures)` | Wait for first | `SelectUnion` |
| `Io.sleep(io, duration, clock)` | Async sleep | `!void` |
| `Io.cancelRequested(io)` | Check for cancellation | `bool` |

### Key Takeaways

1. **Io is like Allocator** - Pass it everywhere you need I/O
2. **async vs concurrent** - `async` always works, `concurrent` guarantees parallelism
3. **Future.await and Future.cancel are idempotent** - Safe to call multiple times
4. **Same code, different backends** - Write once, run with Threaded/IoUring/Kqueue
5. **No function coloring** - async doesn't infect your API signatures

---

## Further Reading

- [Zig's New Async I/O - Loris Cro](https://kristoff.it/blog/zig-new-async-io/)
- [Zig's New Async I/O (Text Version) - Andrew Kelley](https://andrewkelley.me/post/zig-new-async-io-text-version.html)
- Zig 0.16 Source: `lib/std/Io.zig`, `lib/std/Io/Threaded.zig`
