---
title: "5.7: Return"
weight: 7
---

# Lesson 5.7: Generating Return Statements

Emit return statements correctly.

---

## Goal

Generate C code for `ret` and `ret_void` instructions.

---

## Return Patterns

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        RETURN PATTERNS                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   With value:                                                               │
│     AIR:  ret(%2)                                                           │
│     C:    return t2;                                                        │
│                                                                              │
│   Without value (void):                                                     │
│     AIR:  ret_void()                                                        │
│     C:    return;                                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Generate Return

```
function generateReturn(instr, index):
    switch instr.tag:
        RET:
            value = instr.data.value
            emitIndent()
            emit("return t")
            emit(value)
            emitLine(";")

        RET_VOID:
            emitIndent()
            emitLine("return;")
```

---

## Note About Index

Return instructions don't produce a value, so we don't create a `tN` variable for them.

```
%0 = const_i32(42)    → int32_t t0 = 42;
%1 = ret(%0)          → return t0;     // No t1!
```

---

## Complete Examples

### Return a constant

```
Source:
fn answer() i32 {
    return 42;
}

Generated C:
    int32_t answer() {
        int32_t t0 = 42;
        return t0;
    }
```

### Return an expression

```
Source:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

Generated C:
    int32_t add(int32_t p0, int32_t p1) {
        int32_t t0 = p0;
        int32_t t1 = p1;
        int32_t t2 = t0 + t1;
        return t2;
    }
```

### Void return

```
Source:
fn doNothing() void {
    return;
}

Generated C:
    void doNothing() {
        return;
    }
```

---

## Multiple Returns?

Our simple language has one return at the end. But if you extend it:

```
fn abs(x: i32) i32 {
    if x < 0 {
        return -x;
    }
    return x;
}
```

Each return becomes a C return statement. No special handling needed!

---

## Verify Your Implementation

### Test 1: Return constant
```
AIR:
    %0 = const_i32(0)
    %1 = ret(%0)

Output:
    int32_t t0 = 0;
    return t0;
```

### Test 2: Return expression
```
AIR:
    %0 = param_get(0)
    %1 = const_i32(1)
    %2 = add_i32(%0, %1)
    %3 = ret(%2)

Output:
    int32_t t0 = p0;
    int32_t t1 = 1;
    int32_t t2 = t0 + t1;
    return t2;
```

### Test 3: Void return
```
AIR:
    %0 = ret_void()

Output:
    return;
```

### Test 4: Return local
```
AIR:
    %0 = const_i32(5)
    %1 = local_set(0, %0)
    %2 = local_get(0)
    %3 = ret(%2)

Output:
    int32_t t0 = 5;
    local_0 = t0;
    int32_t t2 = local_0;
    return t2;
```

---

## What's Next

Let's handle function calls.

Next: [Lesson 5.8: Calls](../08-gen-calls/) →
