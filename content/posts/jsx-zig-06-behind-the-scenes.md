+++
title = "Building UIs in Zig: Part 6 - Behind the Scenes"
date = 2024-12-08
draft = false
series = ["JSX in Zig"]
tags = ["zig", "ui", "advanced", "internals"]
+++

You've seen the API. Now let's look at the actual code. This is a sneak peek into how the JSX framework is built.

## The Node Struct

Everything starts with `Node`. Here's what it actually looks like:

```zig
pub const Node = struct {
    kind: Kind,
    style: Style = .{},
    props: Props = .{},
    children: []const Node = &.{},

    pub const Kind = enum {
        // Layout
        col, row, div, center, stack, scroll,
        // Content
        text, icon, spacer, divider,
        // Interactive
        button, toggle, input, slider,
        // Containers
        card, list, item, modal,
    };

    pub const Props = struct {
        // Content
        label: ?[]const u8 = null,
        value: ?[]const u8 = null,

        // State
        active: bool = false,
        disabled: bool = false,
        focused: bool = false,

        // Events (handler indices)
        on_press: ?usize = null,
        on_change: ?usize = null,
        on_focus: ?usize = null,
    };
};
```

Four fields. That's it. The `kind` tells the renderer what to draw, `style` controls appearance, `props` holds content and state, and `children` is just a slice of more nodes.

## The Builder Functions

When you write `jsx.col("gap-4 p-6", &.{...})`, here's what happens:

```zig
pub fn col(comptime classes: []const u8, children: []const Node) Node {
    return .{
        .kind = .col,
        .style = comptime blk: {
            var style = tw(classes);
            style.display = .flex;
            style.flex_dir = .col;
            break :blk style;
        },
        .children = children,
    };
}
```

The `comptime blk:` block parses Tailwind classes at compile time and sets up flex direction. The result is a `Node` struct with everything baked in.

Text and buttons work similarly:

```zig
pub fn text(label: []const u8, comptime classes: []const u8) Node {
    return .{
        .kind = .text,
        .style = comptime tw(classes),
        .props = .{ .label = label },
    };
}

pub fn button(label: []const u8, comptime classes: []const u8) Node {
    return .{
        .kind = .button,
        .style = comptime tw(classes),
        .props = .{ .label = label },
    };
}
```

## Method Chaining

How does `.onPress(E.increment)` work? Each modifier returns a new Node:

```zig
pub fn onPress(self: Node, handler: anytype) Node {
    var n = self;
    n.props.on_press = toHandler(handler);
    return n;
}

pub fn fg(self: Node, color: Color) Node {
    var n = self;
    n.style.fg = color;
    return n;
}

pub fn active(self: Node, a: bool) Node {
    var n = self;
    n.props.active = a;
    return n;
}
```

The `toHandler` function converts enums to `usize`:

```zig
fn toHandler(handler: anytype) usize {
    const T = @TypeOf(handler);
    if (T == usize) return handler;
    if (@typeInfo(T) == .@"enum") return @intFromEnum(handler);
    @compileError("Handler must be usize or enum");
}
```

So `jsx.button("+", "").onPress(E.increment)` creates a Node, then returns a modified copy with `on_press` set.

## The Style Struct

The `Style` struct holds all visual properties:

```zig
pub const Style = struct {
    // Layout
    display: Display = .block,
    flex_dir: FlexDir = .row,
    flex: i32 = 0,
    gap: i32 = 0,
    items: Align = .start,
    justify: Justify = .start,

    // Spacing (pixels)
    p: i32 = 0,       // padding all
    px: ?i32 = null,  // padding x
    py: ?i32 = null,  // padding y
    m: i32 = 0,       // margin all
    mt: ?i32 = null,  // margin top
    // ... etc

    // Colors
    bg: ?Color = null,
    fg: ?Color = null,

    // Borders
    rounded: Rounded = .none,
    border_width: i32 = 0,
};
```

Why `?i32` for directional spacing? So we can tell "not set" from "explicitly zero". The getters cascade:

```zig
pub fn getMarginTop(self: Style) i32 {
    return self.mt orelse self.my orelse self.m;
}
```

`mt-4` overrides `my-2` which overrides `m-1`.

## The Renderer

Here's the actual render loop:

```zig
pub fn render(self: *Renderer, root: Node) void {
    self.events.beginFrame(rl.getFrameTime());
    rl.clearBackground(DEFAULT_BG);
    self.renderNode(&ctx, root, self.bounds);
}

fn renderNode(self: *Renderer, ctx: *RenderCtx, node: Node, bounds: Rect) void {
    switch (node.kind) {
        .col => self.renderCol(ctx, node, bounds),
        .row => self.renderRow(ctx, node, bounds),
        .text => widgets.renderText(ctx, node, bounds),
        .button => widgets.renderButton(ctx, node, bounds),
        .toggle => widgets.renderToggle(ctx, node, bounds),
        // ... etc
    }
}
```

A switch on `node.kind` dispatches to the right renderer. Layout nodes recurse into children, leaf nodes just draw.

## Column Layout

Here's how `renderColChildren` actually works:

```zig
fn renderColChildren(self: *Renderer, ctx: *RenderCtx, node: Node, content: Rect) void {
    const gap = node.style.gap;
    const n = node.children.len;
    if (n == 0) return;

    // Calculate how much space flex children get
    const calc = layout.FlexLayout.calcSizes(
        node.children, content.h, gap, widgets.measureH
    );

    var y = content.y;
    for (node.children) |child| {
        const mt = child.style.getMarginTop();
        const ml = child.style.getMarginLeft();
        const mr = child.style.getMarginRight();

        // Position with margins
        var child_x = content.x + ml;
        var child_w = content.w - ml - mr;

        // Handle mx-auto centering
        if (child.style.hasAutoMarginX()) {
            const actual_w = widgets.measureBaseW(child);
            child_x = content.x + @divFloor(content.w - actual_w, 2);
            child_w = actual_w;
        }

        // Height: flex children expand, others use natural size
        const child_h = if (child.style.flex > 0)
            @max(getChildSize(child, calc.flex_unit), widgets.measureBaseH(child))
        else
            widgets.measureBaseH(child);

        // Render at position with top margin applied
        self.renderNode(ctx, child, Rect.init(child_x, y + mt, child_w, child_h));

        // Advance by total height including margins
        y += widgets.measureH(child);
        y += gap;
    }
}
```

The key insight: `measureBaseH` returns content height, `measureH` returns content + margins. We render at `y + mt` (applying top margin), then advance by the full measured height.

## Flex Calculation

How does `flex-1` work? The `calcSizes` function figures out how much space each flex child gets:

```zig
fn calcSizes(children: []const Node, available: i32, gap: i32, measureFn: fn(Node) i32) FlexCalc {
    var fixed_total: i32 = 0;
    var flex_total: i32 = 0;

    for (children) |child| {
        if (child.style.flex > 0) {
            flex_total += child.style.flex;
        } else {
            fixed_total += measureFn(child);
        }
    }

    // Space after fixed children and gaps
    const gaps = @intCast(i32, children.len - 1) * gap;
    const remaining = available - fixed_total - gaps;

    // Each flex unit gets this many pixels
    const flex_unit = if (flex_total > 0)
        @divFloor(remaining, flex_total)
    else
        0;

    return .{ .flex_unit = flex_unit };
}
```

If you have three children: fixed (50px), `flex-1`, `flex-2`, and 300px available with 10px gaps:

1. Fixed space: 50px
2. Gaps: 20px (2 gaps)
3. Remaining: 230px
4. Total flex: 3
5. Per unit: 76px
6. First flex child: 76px, second: 152px

## Widget Rendering

Here's how a button actually gets drawn:

```zig
pub fn renderButton(ctx: *RenderCtx, node: Node, bounds: Rect) void {
    const hover = isHovered(bounds);
    const press = hover and rl.isMouseButtonDown(.left);

    // Background color based on state
    const bg = if (node.props.disabled)
        DEFAULT_BG_SECONDARY
    else if (press)
        DEFAULT_BG_ACTIVE
    else if (hover)
        DEFAULT_BG_HOVER
    else
        resolveColor(node.style.bg) orelse DEFAULT_BG_SECONDARY;

    // Draw rounded rectangle
    const radius = node.style.getBorderRadius();
    const roundness = radius / @as(f32, @floatFromInt(bounds.h));
    rl.drawRectangleRounded(bounds.toRaylib(), roundness, 8, bg);

    // Draw label centered
    if (node.props.label) |label| {
        const slice = ctx.toZ(label);
        const font_size = node.style.getFontSize();
        const text_w = rl.measureText(slice, font_size);
        const tx = bounds.x + @divFloor(bounds.w - text_w, 2);
        const ty = bounds.y + @divFloor(bounds.h - font_size, 2);
        rl.drawText(slice, tx, ty, font_size, DEFAULT_TEXT);
    }

    // Handle click - queue the event
    if (!node.props.disabled and hover and rl.isMouseButtonPressed(.left)) {
        if (node.props.on_press) |idx| ctx.events.queue(idx);
    }
}
```

State flows from props (disabled, active), visual feedback comes from hover/press detection, and clicks queue events for later dispatch.

## Measuring

How do we know a button is 36px tall? The `measureBaseH` function:

```zig
pub fn measureBaseH(node: Node) i32 {
    if (node.style.h) |h| if (h > 0) return h;

    switch (node.kind) {
        .col, .card, .modal => {
            // Vertical stack: sum of children
            var total: i32 = 0;
            for (node.children) |child| total += measureH(child);
            const gaps = (node.children.len - 1) * node.style.gap;
            const pad = node.style.getPadTop() + node.style.getPadBottom();
            return total + gaps + pad;
        },
        .row, .div, .center => {
            // Horizontal: max of children
            var max_h: i32 = 0;
            for (node.children) |child| {
                const h = measureH(child);
                if (h > max_h) max_h = h;
            }
            return max_h + node.style.getPadTop() + node.style.getPadBottom();
        },
        .text => return switch (node.style.text_size) {
            .xs => 16, .sm => 18, .base => 22, .lg => 26,
            .xl => 32, .x2l => 40, .x3l => 48, .x4l => 56,
        },
        .button, .toggle, .input => return 36 + node.style.getPadTop() + node.style.getPadBottom(),
        .divider => return 1,
        .spacer => return 0,
        else => return 32,
    }
}
```

Containers recurse, widgets return constants, text sizes are predefined. Simple.

## Event Dispatch

After rendering, `flush()` calls the queued handlers:

```zig
pub fn flush(self: *EventManager) void {
    for (0..self.count) |i| {
        const idx = self.queue[i];
        if (idx < self.handlers.len) {
            self.handlers[idx]();
        }
    }
    self.count = 0;
}
```

Events are just indices into a handler array. No closures, no allocations.

## The Full Picture

When you write:

```zig
const view = jsx.col("gap-4 p-6", &.{
    jsx.text("Hello", "text-2xl"),
    jsx.button("+", "bg-green-500").onPress(E.increment),
});
renderer.render(view);
```

1. `jsx.col` creates a Node with parsed style and children slice
2. `jsx.text` and `jsx.button` create child Nodes
3. `.onPress()` sets `props.on_press` to the enum value
4. `render()` walks the tree, calculates layout, draws each node
5. Button detects click, queues handler index
6. `flush()` calls `handlers[@intFromEnum(E.increment)]`

No heap allocation. No virtual DOM. No diffing. Just struct construction and a tree walk.

---

*The beauty is in the simplicity. Each piece does one thing well.*
