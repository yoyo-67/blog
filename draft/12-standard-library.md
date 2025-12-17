---
title: "Part 12: The Standard Library - Don't Reinvent the Wheel"
---

# Part 12: The Standard Library - Don't Reinvent the Wheel

In this article, we'll explore Zig's standard library (std). Knowing what's available helps you write better code faster - why reinvent what's already been carefully designed and tested?

The Zig standard library is a masterpiece of careful design. It follows these principles:
- **Explicit over implicit** - No hidden allocations, no global state
- **Composable** - Small interfaces that work together
- **Zero-cost abstractions** - Comptime evaluation eliminates overhead
- **Cross-platform** - Same API everywhere

---

## Part 1: Overview - What's in std?

### The Standard Library Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    STD ORGANIZATION                          │
│                                                              │
│  std/                                                        │
│  ├── Data Structures                                         │
│  │   ├── ArrayList, ArrayHashMap, HashMap                   │
│  │   ├── LinkedList, SegmentedList, PriorityQueue           │
│  │   └── BitSet, BufMap, BufSet                             │
│  │                                                          │
│  ├── Memory                                                  │
│  │   ├── mem (slices, alignment, comparison)                │
│  │   └── heap (allocators: Arena, GPA, Page, Fixed)         │
│  │                                                          │
│  ├── I/O                                                     │
│  │   ├── Io (Reader, Writer interfaces)                     │
│  │   ├── fs (File, Dir, path operations)                    │
│  │   └── net (TCP, UDP, addresses)                          │
│  │                                                          │
│  ├── Text & Formats                                          │
│  │   ├── fmt (formatting, printing)                         │
│  │   ├── json (parse, format)                               │
│  │   └── unicode, ascii                                     │
│  │                                                          │
│  ├── Concurrency                                             │
│  │   ├── Thread (spawn, join)                               │
│  │   └── Mutex, RwLock, Semaphore, Condition                │
│  │                                                          │
│  ├── Algorithms                                              │
│  │   ├── sort (insertion, heap, pdq)                        │
│  │   ├── math (arithmetic, trig, special functions)         │
│  │   └── hash (Wyhash, CRC, crypto hashes)                  │
│  │                                                          │
│  ├── System                                                  │
│  │   ├── os, posix (syscalls, platform APIs)                │
│  │   ├── process (spawn, env, args)                         │
│  │   └── time (timestamps, sleep, timers)                   │
│  │                                                          │
│  ├── Security                                                │
│  │   └── crypto (AES, ChaCha, SHA, signatures)              │
│  │                                                          │
│  ├── Compression                                             │
│  │   └── compress (gzip, zstd, lzma, xz)                    │
│  │                                                          │
│  └── Development                                             │
│      ├── testing (expect, allocator)                        │
│      ├── debug (print, panic, stack traces)                 │
│      └── log (structured logging)                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### How to Import

```zig
const std = @import("std");

// Access modules
const fs = std.fs;
const mem = std.mem;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
```

---

## Part 2: Memory Management - Allocators

Zig doesn't hide allocations. Every allocation is explicit, and allocators are passed as parameters.

**Use Cases for Explicit Allocators:**
- **Embedded systems** - Use FixedBufferAllocator with no heap
- **Games** - Arena per frame, free everything at once
- **Servers** - Arena per request, automatic cleanup
- **CLI tools** - GPA in debug for leak detection, c_allocator in release
- **Libraries** - Accept allocator parameter, caller controls memory

### The Allocator Interface (VTable-based)

The Allocator uses a VTable just like Reader/Writer - it's a pointer to function pointers:

```zig
// From std/mem/Allocator.zig
pub const Allocator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        alloc: *const fn(...) ?[*]u8,
        resize: *const fn(...) bool,
        remap: *const fn(...) ?[*]u8,
        free: *const fn(...) void,
    };
};
```

### Available Allocators

```
┌─────────────────────────────────────────────────────────────┐
│                    ALLOCATOR TYPES                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PageAllocator                                               │
│    Allocates directly from OS (mmap/VirtualAlloc)           │
│    Best for: large, long-lived allocations                  │
│    const alloc = std.heap.page_allocator;                   │
│                                                              │
│  FixedBufferAllocator                                        │
│    Allocates from a fixed-size buffer you provide           │
│    Best for: no-heap scenarios, embedded                    │
│    var buf: [4096]u8 = undefined;                           │
│    var fba = std.heap.FixedBufferAllocator.init(&buf);      │
│                                                              │
│  ArenaAllocator                                              │
│    Bump allocator - fast alloc, free all at once            │
│    Best for: request handling, parsing, temporary work      │
│    var arena = std.heap.ArenaAllocator.init(backing);       │
│    defer arena.deinit();                                    │
│                                                              │
│  GeneralPurposeAllocator (DebugAllocator)                    │
│    Full-featured with leak detection, double-free checks    │
│    Best for: development, testing                           │
│    var gpa = std.heap.GeneralPurposeAllocator(.{}){};       │
│    defer _ = gpa.deinit();                                  │
│                                                              │
│  MemoryPool                                                  │
│    Fixed-size object pool                                   │
│    Best for: many same-sized allocations                    │
│                                                              │
│  c_allocator                                                 │
│    Wraps malloc/free (when linking libc)                    │
│    const alloc = std.heap.c_allocator;                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Choosing the Right Allocator

```
┌─────────────────────────────────────────────────────────────┐
│                 ALLOCATOR DECISION TREE                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  "I'm writing tests"                                         │
│     └─▶ std.testing.allocator (detects leaks!)              │
│                                                              │
│  "I need to track down memory bugs"                          │
│     └─▶ GeneralPurposeAllocator (debug mode)                │
│                                                              │
│  "I have a fixed-size buffer, no heap allowed"               │
│     └─▶ FixedBufferAllocator                                │
│                                                              │
│  "Everything freed at once at end of scope"                  │
│     └─▶ ArenaAllocator (fastest for batch work)             │
│                                                              │
│  "I'm allocating many objects of same size"                  │
│     └─▶ MemoryPool                                          │
│                                                              │
│  "I need raw pages from OS"                                  │
│     └─▶ page_allocator                                      │
│                                                              │
│  "I'm linking libc and want malloc/free"                     │
│     └─▶ c_allocator                                         │
│                                                              │
│  "Production code, general purpose"                          │
│     └─▶ GeneralPurposeAllocator (or c_allocator)            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Practical Example: Arena for Request Handling

```zig
fn handleRequest(backing_allocator: Allocator) !void {
    // Arena for this request - everything freed at end
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena.deinit();  // Frees ALL allocations at once

    const allocator = arena.allocator();

    // All these allocations are freed together
    var list: std.ArrayList(u8) = .empty;
    try list.append(allocator, 'a');
    var map = std.StringHashMap(i32).init(allocator);
    const buffer = try allocator.alloc(u8, 1024);

    // Process request...
    // No need to free individual allocations!
}
```

### FixedBufferAllocator - No Heap Required

```zig
const std = @import("std");

pub fn main() !void {
    // Stack-allocated buffer - no heap needed!
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    // Use like any allocator
    var list: std.ArrayList(u8) = .empty;
    try list.appendSlice(allocator, "Hello!");

    // Check how much space remains
    const remaining = fba.buffer.len - fba.end_index;
    std.debug.print("Space remaining: {} bytes\n", .{remaining});
}
```

### MemoryPool - Efficient Same-Size Allocations

```zig
const std = @import("std");

const Node = struct {
    data: i32,
    next: ?*Node,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Pool for Node-sized allocations
    var pool = std.heap.MemoryPool(Node).init(gpa.allocator());
    defer pool.deinit();

    // Fast allocation - no size calculation needed
    const node1 = try pool.create();
    node1.* = .{ .data = 42, .next = null };

    const node2 = try pool.create();
    node2.* = .{ .data = 100, .next = node1 };

    // Return to pool (doesn't call OS)
    pool.destroy(node1);
}
```

---

## Part 3: Data Structures

**Use Cases:**
- **ArrayList** - Building strings, collecting results, dynamic buffers
- **HashMap** - Caching, lookup tables, deduplication
- **PriorityQueue** - Task schedulers, Dijkstra's algorithm
- **LinkedList** - LRU cache, undo/redo stacks
- **BoundedArray** - Fixed-capacity stack buffers (no allocator needed)

### ArrayList - Dynamic Array

A growable array backed by an allocator. Use when you don't know the size upfront.

**Note:** In Zig 0.15+, ArrayList doesn't store the allocator internally. You pass it to each method.

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create - initialize with .empty, pass allocator to methods
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(allocator);  // Pass allocator to deinit

    // Add elements - allocator passed to each method
    try list.append(allocator, 1);
    try list.append(allocator, 2);
    try list.appendSlice(allocator, &[_]i32{ 3, 4, 5 });

    // Access
    const first = list.items[0];            // Direct slice access O(1)
    const last = list.getLast();            // Last element O(1)

    // Iterate - use the underlying slice
    for (list.items) |item| {
        std.debug.print("{} ", .{item});
    }

    // Remove - no allocator needed for removes
    _ = list.pop();                         // Remove last O(1)
    _ = list.orderedRemove(0);              // Remove at index O(n) - preserves order
    _ = list.swapRemove(0);                 // Remove at index O(1) - changes order!

    // Convert to owned slice - transfers ownership, list becomes empty
    const owned = try list.toOwnedSlice(allocator);
    defer allocator.free(owned);
}
```

**Key ArrayList Methods:**
| Method | Time | Description |
|--------|------|-------------|
| `init(allocator)` | O(1) | Create empty list |
| `deinit()` | O(1) | Free memory |
| `append(item)` | O(1)* | Add to end (*amortized) |
| `appendSlice(slice)` | O(n) | Add multiple items |
| `pop()` | O(1) | Remove and return last |
| `orderedRemove(i)` | O(n) | Remove at index, keep order |
| `swapRemove(i)` | O(1) | Remove at index, swap with last |
| `toOwnedSlice()` | O(1) | Transfer ownership of items |
| `ensureTotalCapacity(n)` | O(n) | Pre-allocate space |

### HashMap - Key-Value Storage

Hash table for O(1) average lookups. Choose the right variant:

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // StringHashMap - for string keys (most common)
    var map = std.StringHashMap(i32).init(allocator);
    defer map.deinit();

    // Insert - put() overwrites existing keys
    try map.put("one", 1);
    try map.put("two", 2);
    try map.put("three", 3);

    // Get - returns optional (null if not found)
    if (map.get("one")) |value| {
        std.debug.print("one = {}\n", .{value});
    }

    // getPtr - get pointer to value (for modification)
    if (map.getPtr("one")) |ptr| {
        ptr.* += 10;  // Modify in place
    }

    // Check existence without getting value
    const exists = map.contains("two");

    // Iterate all entries
    var it = map.iterator();
    while (it.next()) |entry| {
        std.debug.print("{s} = {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    // Remove - returns removed value if existed
    _ = map.remove("one");

    // AutoHashMap - for any hashable key type
    var int_map = std.AutoHashMap(i32, []const u8).init(allocator);
    defer int_map.deinit();
    try int_map.put(42, "answer");

    // getOrPut - get existing or create new entry
    const result = try map.getOrPut("new_key");
    if (!result.found_existing) {
        result.value_ptr.* = 999;  // Initialize new entry
    }
}
```

**HashMap Variants:**
| Type | Use Case |
|------|----------|
| `StringHashMap(V)` | String keys (uses string hash) |
| `AutoHashMap(K, V)` | Any key with default hash |
| `ArrayHashMap(K, V)` | Preserves insertion order |
| `HashMap(K, V, ctx, max_load)` | Custom hash function |

**Key HashMap Methods:**
| Method | Time | Description |
|--------|------|-------------|
| `put(key, value)` | O(1)* | Insert or update |
| `get(key)` | O(1) | Get value or null |
| `getPtr(key)` | O(1) | Get pointer to value |
| `getOrPut(key)` | O(1)* | Get or create entry |
| `contains(key)` | O(1) | Check if key exists |
| `remove(key)` | O(1) | Remove entry |
| `count()` | O(1) | Number of entries |
| `iterator()` | O(1) | Get iterator |

### Other Data Structures

#### ArrayHashMap - Ordered HashMap
Like HashMap but remembers insertion order. Use when you need to iterate in the order items were added.

```zig
var map = std.StringArrayHashMap(i32).init(allocator);
try map.put("first", 1);   // Will be iterated first
try map.put("second", 2);  // Will be iterated second
```

#### BoundedArray - Stack-Allocated Dynamic Array
ArrayList that lives on the stack with fixed max capacity. No allocator needed - perfect for small, temporary buffers.

```zig
// Can hold up to 100 bytes, no heap allocation!
var arr = std.BoundedArray(u8, 100){};
try arr.appendSlice("hello");
std.debug.print("{s}\n", .{arr.slice()});  // "hello"
```

#### PriorityQueue - Always Get Min/Max First
A heap that always gives you the smallest (or largest) element in O(1). Use for:
- **Task scheduling** - Process highest priority task first
- **Dijkstra's algorithm** - Always expand shortest path
- **Event systems** - Process earliest event first

```zig
const std = @import("std");

fn lessThan(context: void, a: i32, b: i32) std.math.Order {
    _ = context;
    return std.math.order(a, b);
}

pub fn main() !void {
    var pq = std.PriorityQueue(i32, void, lessThan).init(allocator, {});
    defer pq.deinit();

    try pq.add(5);
    try pq.add(1);
    try pq.add(3);

    // Always removes the SMALLEST element
    std.debug.print("{}\n", .{pq.remove()});  // 1
    std.debug.print("{}\n", .{pq.remove()});  // 3
    std.debug.print("{}\n", .{pq.remove()});  // 5
}
```

#### DoublyLinkedList - O(1) Insert/Remove Anywhere
Each node points to both next AND previous. Use when you need fast insertion/removal at arbitrary positions (not just ends).

**Note:** In Zig 0.15+, DoublyLinkedList is *intrusive* - you embed the Node in your own struct and use `@fieldParentPtr` to get the data.

```zig
const std = @import("std");

// Embed the Node in your data struct
const MyData = struct {
    value: i32,
    node: std.DoublyLinkedList.Node = .{},

    // Helper to get data from node pointer
    fn fromNode(node: *std.DoublyLinkedList.Node) *MyData {
        return @fieldParentPtr("node", node);
    }
};

pub fn main() void {
    var list: std.DoublyLinkedList = .{};

    // Create data with embedded nodes
    var data1 = MyData{ .value = 1 };
    var data2 = MyData{ .value = 2 };
    var data3 = MyData{ .value = 3 };

    list.append(&data1.node);  // [1]
    list.append(&data2.node);  // [1, 2]
    list.prepend(&data3.node); // [3, 1, 2]

    // O(1) removal from middle (if you have the node)
    list.remove(&data1.node);  // [3, 2]

    // Iterate forward
    var it = list.first;
    while (it) |node| : (it = node.next) {
        const data = MyData.fromNode(node);
        std.debug.print("{} ", .{data.value});
    }
}
```

**Why intrusive?** No allocations needed for the list itself - nodes are part of your data. Great for embedded systems and performance-critical code.

#### BitSet - Compact Boolean Storage
Store millions of true/false values using 1 bit each (not 1 byte). Use for:
- **Bloom filters** - Probabilistic membership testing
- **Seen tracking** - Mark visited nodes in graph traversal
- **Feature flags** - Store many on/off settings efficiently

```zig
const std = @import("std");

pub fn main() void {
    // 64 bits = 64 boolean values in just 8 bytes!
    var bits = std.StaticBitSet(64).initEmpty();

    bits.set(0);     // Mark bit 0 as true
    bits.set(5);     // Mark bit 5 as true
    bits.set(63);    // Mark bit 63 as true

    // Check if bit is set
    if (bits.isSet(5)) {
        std.debug.print("Bit 5 is set!\n", .{});
    }

    // Count how many bits are set
    const count = bits.count();  // 3

    // Toggle a bit
    bits.toggle(5);  // Now bit 5 is false

    // For larger sets, use DynamicBitSet (heap allocated)
    var dynamic = try std.DynamicBitSet.initEmpty(allocator, 1_000_000);
    defer dynamic.deinit();
}
```

**Data Structure Selection Guide:**
| Need | Use |
|------|-----|
| Dynamic array, unknown size | `ArrayList` |
| Small buffer, no heap | `BoundedArray` |
| Key-value lookup | `HashMap` / `StringHashMap` |
| Ordered key-value | `ArrayHashMap` |
| Always get min/max | `PriorityQueue` |
| Fast insert/remove anywhere | `DoublyLinkedList` |
| Track many booleans | `BitSet` / `DynamicBitSet` |

---

## Part 4: I/O - Readers and Writers

### Understanding VTables in Zig

Before diving into I/O, let's understand **VTables** - the pattern Zig uses for runtime polymorphism.

**What is a VTable?**

A VTable (Virtual Table) is a struct containing function pointers. It enables runtime polymorphism without inheritance - different types can share the same interface.

```zig
const std = @import("std");

// This is what a VTable looks like in Zig's I/O system
pub const Reader = struct {
    // Pointer to the VTable (the "virtual function table")
    vtable: *const VTable,
    // Internal buffer for buffering reads
    buffer: []u8,
    // Current position in buffer
    seek: usize,
    // End of valid data in buffer
    end: usize,

    // The VTable defines the actual behavior
    pub const VTable = struct {
        // Function pointer for streaming data
        stream: *const fn (r: *Reader, w: *Writer, limit: Limit) StreamError!usize,
        // Function pointer for discarding data
        discard: *const fn (r: *Reader, limit: Limit) Error!usize,
        // ... more function pointers
    };
};
```

**Why VTables?**

```
┌─────────────────────────────────────────────────────────────┐
│                    WHY VTABLES?                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Problem: You want one function to work with different      │
│           types (file, network, memory buffer)              │
│                                                              │
│  Solution A: Comptime generics                              │
│    ✓ Zero runtime cost                                      │
│    ✗ Code bloat (one copy per type)                         │
│    ✗ Can't switch types at runtime                          │
│                                                              │
│  Solution B: VTables (runtime polymorphism)                 │
│    ✓ Single code path for all types                         │
│    ✓ Can switch types at runtime                            │
│    ✗ Small function call overhead                           │
│                                                              │
│  Zig's I/O uses VTables because:                            │
│    - I/O sources change at runtime (user opens file)        │
│    - Code size matters more than nanoseconds                │
│    - Composability (wrap reader in another reader)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Use Cases for VTables:**
- **Plugin systems** - Load behavior at runtime
- **I/O abstraction** - Same code for files, sockets, memory
- **Testing** - Inject mock implementations
- **Composition** - Wrap types to add features (buffering, limiting)

### The I/O Design (Zig 0.15+)

Zig's I/O system uses VTable-based `Reader` and `Writer` types. This allows any I/O source to be used interchangeably.

```
┌─────────────────────────────────────────────────────────────┐
│                    I/O ARCHITECTURE                          │
│                                                              │
│     ┌─────────────────────────────────────────────┐         │
│     │              Reader (VTable-based)           │         │
│     │  Fields: vtable, buffer, seek, end          │         │
│     │  Methods: stream(), discard(), readVec()    │         │
│     └─────────────────────────────────────────────┘         │
│                          ▲                                   │
│                          │ different vtables                │
│     ┌────────────┬───────┴────────┬─────────────┐           │
│     │            │                │             │           │
│  File.Reader  net.Stream    Reader.fixed()   Limited       │
│                                                              │
│     ┌─────────────────────────────────────────────┐         │
│     │              Writer (VTable-based)           │         │
│     │  Fields: vtable, buffer, end                │         │
│     │  Methods: write(), writeAll(), print()      │         │
│     └─────────────────────────────────────────────┘         │
│                          ▲                                   │
│                          │ different vtables                │
│     ┌────────────┬───────┴────────┬─────────────┐           │
│     │            │                │             │           │
│  File.Writer  net.Stream    Writer.fixed()   Allocating    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Use Cases for I/O:**
- **File processing** - Read config files, write logs
- **Network communication** - HTTP clients/servers, TCP sockets
- **Data transformation** - Compress, encrypt, encode data
- **Testing** - Use fixed buffers instead of real files

### File I/O

```zig
const std = @import("std");
const fs = std.fs;

pub fn main() !void {
    // Open file for reading
    const file = try fs.cwd().openFile("input.txt", .{});
    defer file.close();

    // Read entire file
    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);
}

pub fn writeFile() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create/overwrite file
    const file = try fs.cwd().createFile("output.txt", .{});
    defer file.close();

    // In Zig 0.15+, writer takes a buffer for buffering
    var buf: [4096]u8 = undefined;
    var writer = file.writer(&buf);

    // Write string
    try writer.interface.writeAll("Hello, World!\n");

    // Formatted write
    try writer.interface.print("The answer is {d}\n", .{42});
}
```

### Standard I/O

```zig
const std = @import("std");

pub fn main() !void {
    // For simple output, use debug.print (no buffer needed)
    std.debug.print("Hello from debug.print\n", .{});

    // For stdout/stderr with buffering (Zig 0.15+)
    // Use std.fs.File.stdout(), .stderr(), .stdin()
    const stdout = std.fs.File.stdout();
    var buf: [4096]u8 = undefined;
    var writer = stdout.writer(&buf);

    try writer.interface.print("Hello from stdout!\n", .{});
    try writer.interface.flush();
}
```

### File Reading with Buffer (Zig 0.15+)

In Zig 0.15, buffering is built into the reader/writer - you provide the buffer directly:

```zig
const std = @import("std");

pub fn main() !void {
    const file = try std.fs.cwd().openFile("input.txt", .{});
    defer file.close();

    // Reader with built-in buffer (no separate bufferedReader)
    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);

    // Access the std.Io.Reader interface
    var line_buf: [1024]u8 = undefined;
    var line_count: usize = 0;

    // Use interface for read operations
    while (true) {
        const line = reader.interface.readUntilDelimiterOrEof(&line_buf, '\n') catch break;
        if (line == null) break;
        line_count += 1;
    }

    std.debug.print("Lines: {}\n", .{line_count});
}

pub fn writeFile() !void {
    const file = try std.fs.cwd().createFile("output.txt", .{});
    defer file.close();

    // Writer with built-in buffer
    var buf: [4096]u8 = undefined;
    var writer = file.writer(&buf);

    // Write through the interface
    for (0..100) |i| {
        try writer.interface.print("Line {}\n", .{i});
    }

    // Flush remaining buffer to disk
    try writer.interface.flush();
}
```

### Reader Methods - Complete Reference

```
┌─────────────────────────────────────────────────────────────┐
│                   READER METHODS                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Basic Reading:                                              │
│    read(buffer)           Read up to buffer.len bytes       │
│    readAll(buffer)        Fill entire buffer or EOF         │
│    readNoEof(buffer)      Fill buffer, error on EOF         │
│                                                              │
│  Line/Delimiter Reading:                                     │
│    readUntilDelimiter(buf, delim)      Read until delim     │
│    readUntilDelimiterOrEof(buf, delim) Read or EOF          │
│    readUntilDelimiterAlloc(alloc, delim, max)               │
│    skipUntilDelimiterOrEof(delim)      Skip until delim     │
│                                                              │
│  Typed Reading:                                              │
│    readByte()             Read single byte                  │
│    readInt(T, endian)     Read integer of type T            │
│    readStruct(T)          Read struct from bytes            │
│                                                              │
│  Bulk Reading:                                               │
│    readToEndAlloc(alloc, max) Read all into allocated slice │
│    readAllArrayList(list, max) Append to ArrayList          │
│    skipBytes(n, opts)     Skip n bytes                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Writer Methods - Complete Reference

```
┌─────────────────────────────────────────────────────────────┐
│                   WRITER METHODS                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Basic Writing:                                              │
│    write(bytes)           Write bytes, return count written │
│    writeAll(bytes)        Write all bytes                   │
│                                                              │
│  Formatted Writing:                                          │
│    print(fmt, args)       Formatted output                  │
│                                                              │
│  Single Values:                                              │
│    writeByte(byte)        Write single byte                 │
│    writeByteNTimes(b, n)  Write byte n times                │
│    writeInt(T, val, endian) Write integer                   │
│    writeStruct(val)       Write struct as bytes             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### FixedBufferStream - In-Memory I/O

```zig
const std = @import("std");

pub fn main() void {
    var buffer: [100]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    // Write to memory buffer
    const writer = stream.writer();
    writer.print("Hello {s}!", .{"World"}) catch unreachable;

    // Read it back
    stream.reset();  // Seek to beginning
    const reader = stream.reader();
    var read_buf: [50]u8 = undefined;
    const bytes_read = reader.read(&read_buf) catch unreachable;

    std.debug.print("Read: {s}\n", .{read_buf[0..bytes_read]});
}
```

---

## Part 5: File System

**Use Cases:**
- **Config files** - Read/write application settings
- **Build systems** - Walk directories, find source files
- **File managers** - List, copy, delete operations
- **Log rotation** - Write logs, manage old files
- **Temp files** - Create scratch space, clean up on exit

### Directory Operations

```zig
const std = @import("std");
const fs = std.fs;

pub fn main() !void {
    // Get current working directory
    const cwd = fs.cwd();

    // Create directory
    try cwd.makeDir("new_folder");

    // Create nested directories
    try cwd.makePath("a/b/c");

    // Delete
    try cwd.deleteFile("file.txt");
    try cwd.deleteDir("empty_folder");
    try cwd.deleteTree("folder_with_contents");

    // Iterate directory
    var dir = try cwd.openDir(".", .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        std.debug.print("{s} ({s})\n", .{
            entry.name,
            @tagName(entry.kind)
        });
    }
}
```

### Path Operations

```zig
const std = @import("std");
const path = std.fs.path;

pub fn main() void {
    // Join paths
    const full = path.join(allocator, &.{ "home", "user", "file.txt" });
    // Result: "home/user/file.txt"

    // Get components
    const dir = path.dirname("/home/user/file.txt");    // "/home/user"
    const base = path.basename("/home/user/file.txt");  // "file.txt"
    const ext = path.extension("file.txt");             // ".txt"
    const stem = path.stem("file.txt");                 // "file"

    // Normalize
    const normalized = path.normalize("a//b/../c");     // "a/c"

    // Check absolute
    const is_abs = path.isAbsolute("/home/user");       // true
}
```

---

## Part 6: Networking

**Use Cases:**
- **HTTP APIs** - REST clients, webhook handlers
- **Microservices** - Service-to-service communication
- **Proxies** - Forward requests, load balancing
- **Chat apps** - Real-time TCP/UDP communication
- **File transfers** - Upload/download services

### TCP Client

```zig
const std = @import("std");
const net = std.net;

pub fn main() !void {
    // Connect to server
    const stream = try net.tcpConnectToHost(allocator, "example.com", 80);
    defer stream.close();

    // Send HTTP request
    const request = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n";
    try stream.writeAll(request);

    // Read response
    var buf: [4096]u8 = undefined;
    const n = try stream.read(&buf);
    std.debug.print("{s}\n", .{buf[0..n]});
}
```

### TCP Server

```zig
const std = @import("std");
const net = std.net;

pub fn main() !void {
    // Listen on port 8080
    const address = net.Address.parseIp("127.0.0.1", 8080) catch unreachable;
    var server = try address.listen(.{});
    defer server.deinit();

    std.debug.print("Listening on port 8080...\n", .{});

    while (true) {
        // Accept connection
        const connection = try server.accept();
        defer connection.stream.close();

        // Handle client
        var buf: [1024]u8 = undefined;
        const n = try connection.stream.read(&buf);

        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\nHello!");
    }
}
```

### HTTP Client

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Make GET request (Zig 0.15 API uses .location)
    const result = try client.fetch(.{
        .location = .{ .url = "https://httpbin.org/get" },
    });

    std.debug.print("Status: {}\n", .{result.status});
    // Note: For reading response body, provide a response_writer in fetch options
}
```

---

## Part 7: Process Management

**Use Cases:**
- **Build tools** - Run compilers, linters, test frameworks
- **CI/CD** - Execute scripts, deploy applications
- **Shell utilities** - Pipe commands, process output
- **Service managers** - Start/stop daemons, monitor processes
- **Development tools** - Hot reload, watch mode

### Spawning Child Processes

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Spawn a child process - init takes (argv, allocator)
    var child = std.process.Child.init(&.{ "ls", "-la" }, allocator);

    // Configure stdio behavior
    child.stdout_behavior = .Pipe;  // Capture stdout
    child.stderr_behavior = .Inherit;  // Show errors

    // Start the process
    try child.spawn();

    // Read all output
    const stdout = child.stdout.?;
    const output = try stdout.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);

    // Wait for completion
    const term = try child.wait();

    switch (term) {
        .Exited => |code| std.debug.print("Exited with: {}\n", .{code}),
        .Signal => |sig| std.debug.print("Killed by signal: {}\n", .{sig}),
        else => std.debug.print("Other termination\n", .{}),
    }

    std.debug.print("Output:\n{s}\n", .{output});
}
```

### Environment Variables

```zig
const std = @import("std");
const process = std.process;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get single environment variable
    const home = try process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    std.debug.print("HOME = {s}\n", .{home});

    // Check if variable exists (no allocation)
    if (process.hasEnvVarConstant("DEBUG")) {
        std.debug.print("Debug mode enabled\n", .{});
    }

    // Get all environment variables
    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();

    // Iterate all variables
    var it = env_map.iterator();
    while (it.next()) |entry| {
        std.debug.print("{s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
```

### Command Line Arguments

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get args iterator
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    // Process arguments
    while (args.next()) |arg| {
        std.debug.print("Arg: {s}\n", .{arg});
    }

    // Or collect into slice
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    for (argv) |arg| {
        std.debug.print("{s}\n", .{arg});
    }
}
```

### Current Working Directory

```zig
const std = @import("std");
const process = std.process;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get current working directory
    const cwd = try process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    std.debug.print("CWD: {s}\n", .{cwd});

    // Change directory
    try process.changeCurDir("/tmp");

    // Exit process
    // process.exit(0);  // Exit with code 0
}
```

---

## Part 8: JSON

**Use Cases:**
- **API responses** - Parse REST API data
- **Configuration** - Read JSON config files
- **Data exchange** - Serialize/deserialize messages
- **Web services** - Generate JSON responses
- **Logging** - Structured log output

### Parsing JSON

```zig
const std = @import("std");

const Person = struct {
    name: []const u8,
    age: u32,
    emails: []const []const u8,
};

pub fn main() !void {
    const json_str =
        \\{
        \\  "name": "Alice",
        \\  "age": 30,
        \\  "emails": ["alice@example.com", "alice@work.com"]
        \\}
    ;

    // Parse into struct
    const parsed = try std.json.parseFromSlice(Person, allocator, json_str, .{});
    defer parsed.deinit();

    const person = parsed.value;
    std.debug.print("Name: {s}, Age: {}\n", .{ person.name, person.age });

    // Parse into dynamic Value
    const dynamic = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer dynamic.deinit();

    const name = dynamic.value.object.get("name").?.string;
    std.debug.print("Name: {s}\n", .{name});
}
```

### Generating JSON

```zig
const std = @import("std");

const Person = struct {
    name: []const u8,
    age: u32,
};

pub fn main() !void {
    const person = Person{ .name = "Bob", .age = 25 };

    // Use std.json.fmt for easy output
    std.debug.print("JSON: {f}\n", .{std.json.fmt(person, .{})});
    // Output: {"name":"Bob","age":25}

    // Pretty print with indentation
    std.debug.print("Pretty:\n{f}\n", .{std.json.fmt(person, .{ .whitespace = .indent_2 })});
    // Output:
    // {
    //   "name": "Bob",
    //   "age": 25
    // }
}
```

---

## Part 8: Formatting and Printing

### Format Specifiers

```
┌─────────────────────────────────────────────────────────────┐
│                  FORMAT SPECIFIERS                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  {d}    Decimal integer      std.debug.print("{d}", .{42}); │
│  {x}    Hex lowercase        std.debug.print("{x}", .{255});│
│  {X}    Hex uppercase        → "FF"                          │
│  {b}    Binary               std.debug.print("{b}", .{5});  │
│  {o}    Octal                → "5"                           │
│  {e}    Scientific float     std.debug.print("{e}", .{1.5});│
│  {s}    String/slice         std.debug.print("{s}", .{"hi"});│
│  {c}    Character            std.debug.print("{c}", .{'A'}); │
│  {any}  Any type (debug)     std.debug.print("{any}", .{x}); │
│  {}     Default format       std.debug.print("{}", .{42});  │
│                                                              │
│  Width and precision:                                        │
│  {d:5}     Width 5           "   42"                         │
│  {d:0>5}   Zero-padded       "00042"                         │
│  {d:<5}    Left-aligned      "42   "                         │
│  {d:.2}    Precision 2       for floats: "3.14"              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Formatting Examples

```zig
const std = @import("std");

pub fn main() !void {
    // Format to string
    const str = try std.fmt.allocPrint(allocator, "Hello, {s}!", .{"World"});
    defer allocator.free(str);

    // Format to fixed buffer
    var buf: [100]u8 = undefined;
    const result = try std.fmt.bufPrint(&buf, "{d} + {d} = {d}", .{ 2, 2, 4 });

    // Format numbers
    std.debug.print("Decimal: {d}\n", .{42});
    std.debug.print("Hex: 0x{x}\n", .{255});        // 0xff
    std.debug.print("Binary: 0b{b}\n", .{5});       // 0b101
    std.debug.print("Padded: {d:0>8}\n", .{42});    // 00000042

    // Format floats
    std.debug.print("Float: {d:.2}\n", .{3.14159}); // 3.14
    std.debug.print("Sci: {e}\n", .{1234.5});       // 1.2345e+03

    // Comptime formatting
    const comptime_str = std.fmt.comptimePrint("Answer: {d}", .{42});
    // comptime_str is a comptime-known string literal
}
```

---

## Part 9: Sorting and Algorithms

### Sorting

```zig
const std = @import("std");

pub fn main() void {
    var items = [_]i32{ 5, 2, 8, 1, 9, 3 };

    // Sort ascending
    std.mem.sort(i32, &items, {}, std.sort.asc(i32));
    // Result: [1, 2, 3, 5, 8, 9]

    // Sort descending
    std.mem.sort(i32, &items, {}, std.sort.desc(i32));
    // Result: [9, 8, 5, 3, 2, 1]

    // Custom sort
    const Context = struct {
        fn lessThan(_: @This(), a: i32, b: i32) bool {
            return @abs(a) < @abs(b);  // Sort by absolute value
        }
    };
    std.mem.sort(i32, &items, Context{}, Context.lessThan);

    // Binary search (on sorted array)
    const index = std.sort.binarySearch(i32, &items, 5, {}, std.sort.asc(i32));
}
```

### Memory Operations

```zig
const std = @import("std");
const mem = std.mem;

pub fn main() void {
    // Compare
    const equal = mem.eql(u8, "hello", "hello");  // true
    const order = mem.order(u8, "abc", "abd");    // .lt

    // Search
    const slice = "hello world";
    const idx = mem.indexOf(u8, slice, "world");   // 6
    const contains = mem.containsAtLeast(u8, slice, 1, "o");  // true

    // Copy
    var dest: [5]u8 = undefined;
    @memcpy(&dest, "hello");

    // Set
    var buf: [10]u8 = undefined;
    @memset(&buf, 0);  // Zero fill

    // Split
    var it = mem.splitScalar(u8, "a,b,c", ',');
    while (it.next()) |part| {
        std.debug.print("{s}\n", .{part});  // "a", "b", "c"
    }

    // Tokenize (skips empty)
    var tok = mem.tokenizeScalar(u8, "  hello   world  ", ' ');
    // Returns: "hello", "world"

    // Trim
    const trimmed = mem.trim(u8, "  hello  ", " ");  // "hello"
}
```

---

## Part 10: Concurrency

**Use Cases:**
- **Parallel processing** - Process multiple files simultaneously
- **Background tasks** - Async I/O, periodic jobs
- **Web servers** - Handle concurrent connections
- **Data pipelines** - Producer-consumer patterns
- **CPU-bound work** - Utilize multiple cores

### Threads

```zig
const std = @import("std");

fn worker(id: usize) void {
    std.debug.print("Worker {} starting\n", .{id});
    std.time.sleep(1 * std.time.ns_per_s);
    std.debug.print("Worker {} done\n", .{id});
}

pub fn main() !void {
    // Spawn threads
    var threads: [4]std.Thread = undefined;

    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, worker, .{i});
    }

    // Wait for all threads
    for (threads) |t| {
        t.join();
    }
}
```

### Synchronization Primitives

```zig
const std = @import("std");

var mutex = std.Thread.Mutex{};
var counter: i32 = 0;

fn increment() void {
    mutex.lock();
    defer mutex.unlock();
    counter += 1;
}

// Read-Write Lock
var rwlock = std.Thread.RwLock{};

fn read() i32 {
    rwlock.lockShared();
    defer rwlock.unlockShared();
    return counter;
}

fn write(value: i32) void {
    rwlock.lock();
    defer rwlock.unlock();
    counter = value;
}
```

### Thread Pool

```zig
const std = @import("std");

pub fn main() !void {
    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    // Submit work
    for (0..10) |i| {
        try pool.spawn(worker, .{i});
    }

    // Wait for completion
    pool.waitAndWork(null);
}
```

---

## Part 11: Time and Dates

### Timestamps and Sleeping

```zig
const std = @import("std");
const time = std.time;

pub fn main() void {
    // Get current time
    const timestamp = time.timestamp();           // Seconds since epoch
    const millis = time.milliTimestamp();         // Milliseconds
    const nanos = time.nanoTimestamp();           // Nanoseconds

    // Sleep
    time.sleep(1 * time.ns_per_s);                // Sleep 1 second
    time.sleep(500 * time.ns_per_ms);             // Sleep 500ms

    // Measure elapsed time
    var timer = try time.Timer.start();
    // ... do work ...
    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / time.ns_per_ms;

    std.debug.print("Elapsed: {}ms\n", .{elapsed_ms});
}
```

### Time Constants

```zig
const time = std.time;

// Useful constants
const ns_per_us = time.ns_per_us;     // 1,000
const ns_per_ms = time.ns_per_ms;     // 1,000,000
const ns_per_s = time.ns_per_s;       // 1,000,000,000
const s_per_min = time.s_per_min;     // 60
const s_per_hour = time.s_per_hour;   // 3,600
const s_per_day = time.s_per_day;     // 86,400
```

---

## Part 12: Testing

### Writing Tests

```zig
const std = @import("std");
const testing = std.testing;

fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add function" {
    // Basic equality
    try testing.expectEqual(@as(i32, 5), add(2, 3));

    // Expect error
    try testing.expectError(error.OutOfMemory, failingFunction());

    // Expect slice equal
    try testing.expectEqualSlices(u8, "hello", "hello");

    // Expect string equal
    try testing.expectEqualStrings("hello", "hello");

    // Approximate float equality
    try testing.expectApproxEqAbs(@as(f32, 0.1 + 0.2), 0.3, 0.0001);

    // Use test allocator (detects leaks!)
    const allocator = testing.allocator;
    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);  // Forgetting this = test failure!
}

test "expect true/false" {
    try testing.expect(2 + 2 == 4);
    try testing.expect(true);
}
```

### Running Tests

```bash
# Run all tests
zig build test

# Run specific test
zig test src/myfile.zig

# With filter
zig test src/myfile.zig --test-filter "add function"
```

---

## Part 13: Logging

### Structured Logging

```zig
const std = @import("std");

// Create scoped logger
const log = std.log.scoped(.my_module);

pub fn main() void {
    log.debug("Debug message: {}", .{42});
    log.info("Server starting on port {}", .{8080});
    log.warn("Connection timeout", .{});
    log.err("Failed to open file: {s}", .{"config.txt"});
}
```

### Customizing Log Output

```zig
// In your root file
pub const std_options: std.Options = .{
    .log_level = .info,  // Only show info and above

    .logFn = struct {
        fn log(
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            const prefix = "[" ++ level.asText() ++ "] ";
            std.debug.print(prefix ++ format ++ "\n", args);
        }
    }.log,
};
```

---

## Part 14: Cryptography

### Hashing

```zig
const std = @import("std");
const crypto = std.crypto;

pub fn main() void {
    const data = "Hello, World!";

    // SHA-256
    var sha256 = crypto.hash.sha2.Sha256.init(.{});
    sha256.update(data);
    const hash = sha256.finalResult();

    // Or one-liner
    const hash2 = crypto.hash.sha2.Sha256.hash(data, .{});

    // Print as hex
    std.debug.print("SHA256: {x}\n", .{std.fmt.fmtSliceHexLower(&hash)});

    // MD5 (not for security!)
    const md5_hash = crypto.hash.Md5.hash(data, .{});

    // Blake3 (fast)
    const blake3_hash = crypto.hash.Blake3.hash(data, .{});
}
```

### Random Numbers

```zig
const std = @import("std");

pub fn main() void {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        break :blk seed;
    });
    const random = prng.random();

    // Random integer
    const n = random.int(u32);

    // Random in range [0, 100)
    const ranged = random.intRangeAtMost(u32, 0, 99);

    // Random float [0, 1)
    const f = random.float(f64);

    // Random bool
    const b = random.boolean();

    // Shuffle array
    var arr = [_]i32{ 1, 2, 3, 4, 5 };
    random.shuffle(i32, &arr);
}
```

---

## Part 15: Compression

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const data = "Hello, World! " ** 100;  // Repeated text

    // Compress with gzip
    var compressed: std.ArrayList(u8) = .empty;
    defer compressed.deinit(allocator);

    var compressor = try std.compress.gzip.compressor(allocator, compressed.writer(allocator), .{});
    try compressor.write(data);
    try compressor.finish();

    std.debug.print("Original: {} bytes\n", .{data.len});
    std.debug.print("Compressed: {} bytes\n", .{compressed.items.len});
}
```

---

## Part 16: Type Introspection (std.meta)

Zig's comptime capabilities combined with `std.meta` enable powerful metaprogramming:

### Basic Type Information

```zig
const std = @import("std");
const meta = std.meta;

const Person = struct {
    name: []const u8,
    age: u32,
    active: bool,
};

pub fn main() void {
    // Get field names
    const names = meta.fieldNames(Person);
    // names = .{ "name", "age", "active" }

    // Get field info
    const fields = meta.fields(Person);
    inline for (fields) |field| {
        std.debug.print("Field: {s}, Type: {}\n", .{
            field.name,
            field.type,
        });
    }

    // Check if type has a field
    const has_name = meta.fieldIndex(Person, "name") != null;  // true
    const has_foo = meta.fieldIndex(Person, "foo") != null;    // false
}
```

### String to Enum Conversion

```zig
const std = @import("std");
const meta = std.meta;

const Color = enum { red, green, blue };

pub fn main() void {
    // Convert string to enum
    const color = meta.stringToEnum(Color, "red");  // Color.red
    const invalid = meta.stringToEnum(Color, "purple");  // null

    if (color) |c| {
        std.debug.print("Color: {}\n", .{c});
    }
}
```

### Type Comparison and Equality

```zig
const std = @import("std");
const meta = std.meta;

pub fn main() void {
    const a = .{ .x = 1, .y = 2 };
    const b = .{ .x = 1, .y = 2 };
    const c = .{ .x = 1, .y = 3 };

    // Deep equality comparison
    const eq1 = meta.eql(a, b);  // true
    const eq2 = meta.eql(a, c);  // false

    // Works with arrays, structs, unions
    const arr1 = [_]i32{ 1, 2, 3 };
    const arr2 = [_]i32{ 1, 2, 3 };
    const arrays_equal = meta.eql(arr1, arr2);  // true
}
```

### Working with Union Tags

```zig
const std = @import("std");
const meta = std.meta;

const Value = union(enum) {
    int: i32,
    float: f64,
    string: []const u8,
};

pub fn main() void {
    const val = Value{ .int = 42 };

    // Get active tag
    const tag = meta.activeTag(val);  // .int

    // Tag type
    const TagType = meta.Tag(Value);  // enum { int, float, string }
}
```

### Generic Programming with Meta

```zig
const std = @import("std");
const meta = std.meta;

fn printAllFields(value: anytype) void {
    const T = @TypeOf(value);
    const fields = meta.fields(T);

    inline for (fields) |field| {
        const field_value = @field(value, field.name);
        std.debug.print("{s}: {any}\n", .{ field.name, field_value });
    }
}

pub fn main() void {
    const point = .{ .x = 10, .y = 20, .z = 30 };
    printAllFields(point);
    // Output:
    // x: 10
    // y: 20
    // z: 30
}
```

---

## Part 17: Utilities (Base64, Uri, etc.)

### Base64 Encoding/Decoding

```zig
const std = @import("std");
const base64 = std.base64;

pub fn main() !void {
    const data = "Hello, World!";

    // Encode
    var encoded_buf: [100]u8 = undefined;
    const encoded = base64.standard.Encoder.encode(&encoded_buf, data);
    std.debug.print("Encoded: {s}\n", .{encoded});
    // Output: SGVsbG8sIFdvcmxkIQ==

    // Decode
    var decoded_buf: [100]u8 = undefined;
    const decoded_len = try base64.standard.Decoder.calcSizeForSlice(encoded);
    try base64.standard.Decoder.decode(&decoded_buf, encoded);
    std.debug.print("Decoded: {s}\n", .{decoded_buf[0..decoded_len]});

    // URL-safe variant (uses - and _ instead of + and /)
    const url_encoded = base64.url_safe.Encoder.encode(&encoded_buf, data);
    std.debug.print("URL-safe: {s}\n", .{url_encoded});
}
```

### URI Parsing

```zig
const std = @import("std");
const Uri = std.Uri;

pub fn main() !void {
    const url = "https://user:pass@example.com:8080/path?query=value#fragment";

    const uri = try Uri.parse(url);

    std.debug.print("Scheme: {s}\n", .{uri.scheme});          // https
    std.debug.print("Host: {s}\n", .{uri.host.?.raw});        // example.com
    std.debug.print("Port: {?}\n", .{uri.port});              // 8080
    std.debug.print("Path: {s}\n", .{uri.path.raw});          // /path
    std.debug.print("Query: {s}\n", .{uri.query.?.raw});      // query=value
    std.debug.print("Fragment: {s}\n", .{uri.fragment.?.raw}); // fragment

    // Percent decoding
    var buf: [256]u8 = undefined;
    const decoded = Uri.percentDecodeInPlace(buf[0..]);
}
```

### Bit Manipulation (std.math)

```zig
const std = @import("std");
const math = std.math;

pub fn main() void {
    // Overflow-checked arithmetic
    const result = math.add(u8, 200, 100);  // null (overflow)
    const safe = math.add(u8, 100, 50);     // 150

    // Saturating arithmetic
    const saturated = math.sub(u8, 10, 20);  // Would underflow
    // Use @subWithOverflow for explicit handling

    // Power of 2 operations
    const is_pow2 = math.isPowerOfTwo(16);  // true
    const next_pow2 = math.ceilPowerOfTwo(u32, 5);  // 8
    const log2 = math.log2_int(u32, 8);     // 3

    // Min/max
    const minimum = @min(5, 10);  // 5
    const maximum = @max(5, 10);  // 10

    // Clamping
    const clamped = math.clamp(@as(i32, 150), 0, 100);  // 100
}
```

### Unicode Handling

```zig
const std = @import("std");
const unicode = std.unicode;

pub fn main() void {
    const text = "Hello, 世界! 🎉";

    // Iterate UTF-8 codepoints
    var iter = unicode.Utf8View.initUnchecked(text).iterator();
    while (iter.nextCodepoint()) |cp| {
        std.debug.print("U+{X:0>4}\n", .{cp});
    }

    // Count codepoints (not bytes!)
    const len = unicode.utf8CountCodepoints(text) catch 0;
    std.debug.print("Codepoints: {}\n", .{len});

    // Validate UTF-8
    const valid = unicode.utf8ValidateSlice(text);
    std.debug.print("Valid UTF-8: {}\n", .{valid});
}
```

---

## Part 18: Atomic Operations

For lock-free concurrent programming:

### Atomic Values

```zig
const std = @import("std");

var counter = std.atomic.Value(u32).init(0);

fn worker() void {
    for (0..1000) |_| {
        // Atomic increment
        _ = counter.fetchAdd(1, .seq_cst);
    }
}

pub fn main() !void {
    var threads: [4]std.Thread = undefined;

    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, worker, .{});
    }

    for (threads) |t| {
        t.join();
    }

    std.debug.print("Counter: {}\n", .{counter.load(.seq_cst)});
    // Output: Counter: 4000
}
```

### Compare-and-Swap

```zig
const std = @import("std");

var shared = std.atomic.Value(u32).init(0);

fn tryIncrement(expected: u32) bool {
    // Only increment if current value equals expected
    return shared.cmpxchgStrong(
        expected,
        expected + 1,
        .seq_cst,
        .seq_cst,
    ) == null;  // null means success
}

fn incrementUntilSuccess() void {
    while (true) {
        const current = shared.load(.seq_cst);
        if (tryIncrement(current)) break;
        // Failed, retry with new value
    }
}
```

### Memory Ordering

```
┌─────────────────────────────────────────────────────────────┐
│                   MEMORY ORDERING                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  .monotonic   No ordering guarantees (fastest)              │
│               Use for: simple counters, statistics          │
│                                                              │
│  .acquire     Reads can't be reordered before this          │
│               Use for: reading shared data after lock       │
│                                                              │
│  .release     Writes can't be reordered after this          │
│               Use for: publishing data before unlock        │
│                                                              │
│  .acq_rel     Both acquire and release                      │
│               Use for: read-modify-write operations         │
│                                                              │
│  .seq_cst     Full sequential consistency (slowest)         │
│               Use for: when in doubt, correctness first     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 19: Error Handling Patterns

### Error Sets

```zig
const std = @import("std");

// Define custom error set
const FileError = error{
    NotFound,
    PermissionDenied,
    IoError,
};

// Function that returns errors
fn openConfig(path: []const u8) FileError![]const u8 {
    if (path.len == 0) return error.NotFound;
    // ...
    return "config data";
}

// Error union with anyerror
fn process() !void {
    // Can return any error
    const config = try openConfig("config.txt");
    _ = config;
}
```

### Error Handling Strategies

```zig
const std = @import("std");

fn handleErrors() void {
    // 1. try - propagate error up
    const result1 = openFile() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    // 2. catch with default value
    const result2 = openFile() catch "default";

    // 3. catch unreachable (assert no error)
    const result3 = openFile() catch unreachable;

    // 4. if-else with error capture
    if (openFile()) |value| {
        std.debug.print("Got: {s}\n", .{value});
    } else |err| {
        std.debug.print("Error: {}\n", .{err});
    }

    // 5. Switch on error
    openFile() catch |err| switch (err) {
        error.NotFound => std.debug.print("File not found\n", .{}),
        error.PermissionDenied => std.debug.print("Permission denied\n", .{}),
        else => std.debug.print("Other error\n", .{}),
    };

    _ = result1;
    _ = result2;
    _ = result3;
}

fn openFile() ![]const u8 {
    return error.NotFound;
}
```

### errdefer - Cleanup on Error

```zig
const std = @import("std");

fn createResource(allocator: std.mem.Allocator) !*Resource {
    const resource = try allocator.create(Resource);

    // This runs ONLY if function returns error
    errdefer allocator.destroy(resource);

    try resource.init();  // If this fails, resource is freed
    try resource.configure();  // If this fails, resource is freed

    return resource;  // Success - errdefer doesn't run
}

const Resource = struct {
    fn init(self: *Resource) !void { _ = self; }
    fn configure(self: *Resource) !void { _ = self; }
};
```

### Error Return Traces

```zig
const std = @import("std");

fn level3() !void {
    return error.DeepError;
}

fn level2() !void {
    try level3();
}

fn level1() !void {
    try level2();
}

pub fn main() void {
    level1() catch |err| {
        // In debug builds, prints full stack trace
        std.debug.print("Error: {}\n", .{err});

        // Get error return trace
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    };
}
```

---

## Summary: Quick Reference

```
┌─────────────────────────────────────────────────────────────┐
│                    STD QUICK REFERENCE                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  MEMORY                                                      │
│    std.heap.ArenaAllocator       Bump allocator             │
│    std.heap.GeneralPurposeAllocator  Debug allocator        │
│    std.heap.FixedBufferAllocator No heap needed             │
│    std.heap.MemoryPool           Same-size objects          │
│    std.mem.Allocator             Interface                  │
│                                                              │
│  COLLECTIONS                                                 │
│    std.ArrayList(T)              Dynamic array              │
│    std.StringHashMap(V)          String → V map             │
│    std.AutoHashMap(K, V)         K → V map                  │
│    std.PriorityQueue(T)          Heap                       │
│    std.BoundedArray(T, N)        Fixed capacity array       │
│                                                              │
│  I/O                                                         │
│    std.fs.cwd()                  Current directory          │
│    std.fs.File                   File handle                │
│    std.fs.File.stdout/stderr()   Standard streams           │
│    file.reader(&buf)             Buffered reader            │
│    std.io.fixedBufferStream      In-memory I/O              │
│                                                              │
│  TEXT & FORMATS                                              │
│    std.fmt.print()               Formatted output           │
│    std.fmt.allocPrint()          Format to string           │
│    std.json.parseFromSlice()     Parse JSON                 │
│    std.json.fmt()                Generate JSON              │
│    std.base64.standard           Base64 encoding            │
│    std.Uri                       URL parsing                │
│                                                              │
│  ALGORITHMS                                                  │
│    std.mem.sort()                Sort slice                 │
│    std.mem.indexOf()             Find in slice              │
│    std.mem.eql()                 Compare slices             │
│    std.mem.split/tokenize()      Split strings              │
│    std.sort.binarySearch()       Binary search              │
│                                                              │
│  CONCURRENCY                                                 │
│    std.Thread.spawn()            Create thread              │
│    std.Thread.Mutex              Lock                       │
│    std.Thread.Pool               Thread pool                │
│    std.atomic.Value              Lock-free primitives       │
│                                                              │
│  PROCESS                                                     │
│    std.process.Child             Spawn processes            │
│    std.process.getEnvVarOwned()  Get env variable          │
│    std.process.argsWithAllocator Command line args          │
│    std.process.getCwdAlloc()     Current directory          │
│                                                              │
│  TIME                                                        │
│    std.time.timestamp()          Unix timestamp             │
│    std.time.sleep()              Sleep                      │
│    std.time.Timer                Measure elapsed            │
│                                                              │
│  TESTING                                                     │
│    std.testing.expect()          Assert true                │
│    std.testing.expectEqual()     Assert equal               │
│    std.testing.allocator         Leak-detecting allocator   │
│                                                              │
│  NETWORKING                                                  │
│    std.net.tcpConnectToHost()    TCP client                 │
│    std.net.Address.listen()      TCP server                 │
│    std.http.Client               HTTP client                │
│                                                              │
│  META & INTROSPECTION                                        │
│    std.meta.fields()             Get struct fields          │
│    std.meta.stringToEnum()       String to enum             │
│    std.meta.activeTag()          Get union tag              │
│    std.meta.eql()                Deep equality              │
│                                                              │
│  CRYPTO & ENCODING                                           │
│    std.crypto.hash.sha2          SHA-256/512                │
│    std.crypto.hash.Blake3        Fast hash                  │
│    std.Random                    Random numbers             │
│    std.compress.gzip             Compression                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

The standard library is comprehensive and well-designed. Before implementing something yourself, check if std already has it - it probably does, and it's been tested and optimized.

Key principles of std:
- **Explicit allocation** - No hidden allocations
- **Composable interfaces** - Reader/Writer/Allocator work everywhere
- **Cross-platform** - Same API on Linux, Windows, macOS
- **Comptime integration** - Many operations work at compile time

Don't reinvent the wheel - use std!

---

*This article provides a practical guide to the Zig standard library. For complete documentation, see the source code comments in `lib/std/` of your Zig installation.*
