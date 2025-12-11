+++
title = "Building UIs in Zig: Part 5 - Events: Connecting UI to Actions"
date = 2025-12-11
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial"]
+++

Buttons need to do something when clicked. But how? Most frameworks use closures or callbacks. We use something simpler: **indices into an array**.

## The Problem with Closures

In many languages, you'd write:

```javascript
// JavaScript
<button onClick={() => count += 1}>+</button>
```

The closure captures `count`. This requires:
- Heap allocation for the closure
- Reference counting or GC
- Runtime type information

In Zig, closures are complicated. No implicit captures, no heap by default. We need a different approach.

## The Solution: Index-Based Events

Instead of storing closures, we store **indices**:

```zig
// Event enum - each variant is an index
const E = enum(usize) { increment, decrement, reset };
//                         0          1         2

// Handler array - functions at those indices
const handlers = [_]*const fn() void{
    onIncrement,  // index 0
    onDecrement,  // index 1
    onReset,      // index 2
};

// Button stores the index
jsx.button("+", "").onPress(E.increment)  // stores 0
```

When clicked, we call `handlers[0]()` → `onIncrement()`.

## Visual Flow

```
┌─────────────────────────────────────────────┐
│                                             │
│  E = enum { increment, decrement, reset }   │
│              0          1          2        │
│                                             │
│  handlers = [ onIncr,  onDecr,   onReset ]  │
│               [0]       [1]       [2]       │
│                                             │
│  button.onPress(E.increment)                │
│         └─────▶ stores 0                    │
│                                             │
│  on click: handlers[0]() ──▶ onIncr()       │
│                                             │
└─────────────────────────────────────────────┘
```

## The handlers Function

We provide a helper to build the handler array from named fields:

```zig
pub fn handlers(comptime E: type, comptime h: anytype) [enumLen(E)]*const fn() void {
    var arr: [enumLen(E)]*const fn() void = undefined;

    inline for (std.meta.fields(E)) |field| {
        const idx = field.value;
        arr[idx] = @field(h, field.name);
    }

    return arr;
}
```

This lets you write:

```zig
const E = enum(usize) { increment, decrement, reset };

const handlers = jsx.handlers(E, .{
    .increment = onIncrement,
    .decrement = onDecrement,
    .reset = onReset,
});
```

Order doesn't matter. Names are matched at compile time.

## The Event Queue

During rendering, buttons queue events instead of calling handlers immediately:

```zig
pub const EventManager = struct {
    queue: [16]usize = undefined,
    count: usize = 0,
    handlers: []*const fn() void,

    pub fn enqueue(self: *EventManager, handler_idx: usize) void {
        if (self.count < self.queue.len) {
            self.queue[self.count] = handler_idx;
            self.count += 1;
        }
    }

    pub fn flush(self: *EventManager) void {
        for (0..self.count) |i| {
            const idx = self.queue[i];
            if (idx < self.handlers.len) {
                self.handlers[idx]();
            }
        }
        self.count = 0;
    }
};
```

Why queue instead of calling immediately? Rendering should be side-effect free. We render the whole tree, then process events.

## Visual: Button Click Flow

```
Button clicked with on_press = 2
           │
           ▼
    events.enqueue(2)
           │
           ▼
┌─────────────────────────┐
│    Event Queue          │
│  ┌───┬───┬───┬───┐     │
│  │ 2 │   │   │   │     │
│  └───┴───┴───┴───┘     │
│    count = 1            │
└─────────────────────────┘
           │
           ▼ flush() after rendering
┌─────────────────────────┐
│    Handlers Array       │
│  ┌───────────────────┐  │
│  │ 0: onIncrement    │  │
│  │ 1: onDecrement    │  │
│  │ 2: onReset  ◀──────────── call handlers[2]()
│  │ 3: ...            │  │
│  └───────────────────┘  │
└─────────────────────────┘
```

## Accessing State in Handlers

Handlers are plain functions with no parameters. How do they access app state?

Pattern: Use a module-level pointer:

```zig
pub const CounterApp = struct {
    count: i32 = 0,

    var instance: ?*CounterApp = null;

    fn onIncrement() void {
        if (instance) |self| self.count += 1;
    }

    fn onDecrement() void {
        if (instance) |self| self.count -= 1;
    }

    pub fn draw(self: *CounterApp) void {
        instance = self;  // Set before rendering
        // ... render UI ...
    }
};
```

The `instance` pointer is set before each render. Handlers read from it.

## Why This Design?

**No allocations**: Handler indices are just integers. No heap.

**Comptime verified**: If you misspell `.increment`, it won't compile:
```zig
const handlers = jsx.handlers(E, .{
    .incremnt = onIncrement,  // Compile error: no field 'incremnt'
});
```

**IDE friendly**: The enum gives you autocomplete for event names.

**Simple debugging**: An event is just a number. Print it, trace it, inspect it.

## Multiple Events

A single frame can queue multiple events:

```zig
// Click button A and button B in same frame
events.enqueue(0);  // increment
events.enqueue(2);  // reset

// flush() calls both:
// handlers[0]() → onIncrement
// handlers[2]() → onReset
```

## Different Event Types

Different widgets use different events:

```zig
// Press events (buttons)
jsx.button("+", "").onPress(E.increment)

// Change events (toggles, inputs)
jsx.toggle("Dark Mode", "").onChange(E.toggleDark)

// Both on same element
jsx.input("", "").onChange(E.textChanged).onSubmit(E.submit)
```

Each is just a different `?usize` field in Props.

## What's Next

Now you understand the building blocks:
- Nodes (data)
- Builders (convenience)
- Styles (comptime parsing)
- Rendering (tree walking)
- Events (index dispatch)

In Part 6, we'll step back and see WHY this declarative approach is better than the alternative.
