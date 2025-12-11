+++
title = "Building UIs in Zig: Part 8 - The Complete Architecture"
date = 2025-12-11
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "tutorial", "architecture"]
+++

Let's zoom out and see how all the pieces fit together into a complete UI framework.

## The Big Picture

```
┌─────────────────────────────────────────────────┐
│                   Your App                       │
│  State: { count: 5, step: .one }                │
│                    │                             │
│                    ▼                             │
│  View: jsx.col("gap-4", &.{ ... })              │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│               JSX Framework                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ Builder  │  │ Renderer │  │  Events  │      │
│  │ col,row  │  │ Layout+  │  │ Handler  │      │
│  │ text,btn │  │  Draw    │  │ Dispatch │      │
│  └──────────┘  └──────────┘  └──────────┘      │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│                  Raylib                          │
│        drawRect, drawText, getMousePos          │
└─────────────────────────────────────────────────┘
```

Three layers:
1. **Your App** - State and view function
2. **JSX Framework** - Nodes, styles, rendering, events
3. **Raylib** - Actual pixel drawing

## Data Flow

Every frame follows this cycle:

```
┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
│ State  │───▶│ Build  │───▶│ Render │───▶│ Events │──┐
│count=5 │    │  Tree  │    │ Pixels │    │ Queue  │  │
└────────┘    └────────┘    └────────┘    └────────┘  │
     ▲                                                 │
     └─────────────────────────────────────────────────┘
                         next frame
```

1. **State** - Current app data
2. **Build** - View function creates Node tree
3. **Render** - Framework draws tree to pixels
4. **Events** - User clicks queue handler calls
5. **Update** - Handlers modify state
6. **Repeat**

## The Module Structure

If you were building this framework, here's how you might organize it:

```
jsx/
├── root.zig       # Public API (jsx.col, jsx.button, etc.)
├── node.zig       # Node struct, Kind enum, Props
├── builder.zig    # Element constructor functions
├── tw.zig         # Comptime Tailwind parser
├── style.zig      # Style struct and defaults
├── renderer.zig   # Layout calculation, tree walking
├── widgets.zig    # Draw individual node types
├── layout.zig     # Rect, flex calculations
└── events.zig     # Event queue and dispatch
```

## Key Design Decisions

### 1. Immediate Mode

We rebuild the entire UI every frame. No diffing.

```zig
// Every frame:
const view = app.view();  // Build fresh tree
renderer.render(view);     // Draw it
```

**Why?** Simplicity. No virtual DOM, no reconciliation, no stale state bugs.

**Tradeoff**: Can't easily animate between states.

### 2. Comptime Everything

Tailwind classes parsed at compile time. Event enums verified at compile time.

```zig
// At compile time:
const style = tw("gap-4 p-6");  // Parsed to Style struct

// At compile time:
const handlers = jsx.handlers(E, .{ ... });  // Verified
```

**Why?** Zero runtime cost. Errors caught early.

### 3. Value Types

Nodes are values, not heap allocations:

```zig
pub const Node = struct {
    kind: Kind,
    style: Style,
    children: []const Node,  // Slice, not pointer
    props: Props,
};
```

**Why?** No allocator needed. Nodes live on stack or in static memory.

### 4. Index-Based Events

Events are indices into a handler array, not closures:

```zig
const E = enum(usize) { increment, decrement };
handlers[0]() // calls onIncrement
```

**Why?** No heap. Comptime verified. Simple dispatch.

## Frame Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                        FRAME LIFECYCLE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. BUILD                    2. RENDER                         │
│   ┌─────────────┐            ┌─────────────┐                   │
│   │ jsx.col()   │            │ renderNode  │                   │
│   │ jsx.text()  │  ────▶     │     │       │                   │
│   │ jsx.button()│   Node     │     ▼       │                   │
│   └─────────────┘   Tree     │  [layout]   │                   │
│                              │  [draw]     │                   │
│                              │  [hit test] │                   │
│                              └─────────────┘                   │
│                                     │                          │
│                                     ▼                          │
│   4. UPDATE                  3. DISPATCH                        │
│   ┌─────────────┐            ┌─────────────┐                   │
│   │ handler()   │  ◀────     │  flush()    │                   │
│   │ state.x += 1│  calls     │  queue[i]   │                   │
│   └─────────────┘            └─────────────┘                   │
│         │                                                       │
│         └──────────────▶ NEXT FRAME ──────────────────────────▶│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## What You've Learned

1. **Nodes** - UI elements as data structures
2. **Builders** - Convenient node construction
3. **Styles** - Comptime Tailwind parsing
4. **Rendering** - Tree walking and layout
5. **Events** - Index-based handler dispatch
6. **Declarative** - Describe what, not how
7. **Architecture** - How it all fits together

## Next Steps

The foundation is solid. Here are ideas to extend it:

- **More widgets** - slider, checkbox, dropdown, text input
- **Animations** - lerp values over time
- **Keyboard navigation** - focus management
- **Scrolling** - overflow containers
- **Custom rendering** - graphs, charts, canvas

## Final Thoughts

We started with a simple idea: UI elements are data. From there:

- Trees of Nodes describe structure
- Comptime parsing eliminates runtime cost
- Rendering walks the tree and draws
- Events connect interaction to state

The result is a framework where:
- Code reads like UI
- Changes are easy
- Performance is predictable
- Errors are caught early

The beauty is in the simplicity. Each piece does one thing well, and together they make UI development in Zig practical and enjoyable.

---

*This concludes the "Building UIs in Zig" series. Happy building!*
