---
title: "5.9: Program"
weight: 9
---

# Lesson 5.9: Generating Complete Programs

Put together headers, declarations, and functions.

---

## Goal

Generate a complete, compilable C program.

---

## Program Structure

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      C PROGRAM STRUCTURE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   // 1. Headers                                                              │
│   #include <stdint.h>                                                        │
│   #include <stdbool.h>                                                       │
│                                                                              │
│   // 2. Forward declarations (optional)                                      │
│   int32_t add(int32_t p0, int32_t p1);                                      │
│                                                                              │
│   // 3. Function definitions                                                 │
│   int32_t add(int32_t p0, int32_t p1) {                                     │
│       ...                                                                   │
│   }                                                                         │
│                                                                              │
│   int32_t main() {                                                          │
│       ...                                                                   │
│   }                                                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Generate Program

```
function generateProgram(program_air) → string:
    output = StringBuilder()

    // 1. Headers
    emitLine("#include <stdint.h>")
    emitLine("#include <stdbool.h>")
    emitLine("")

    // 2. Forward declarations (optional, for mutual recursion)
    for fn in program_air.functions:
        generateFunctionSignature(fn)
        emitLine(";")
    emitLine("")

    // 3. Function definitions
    for fn in program_air.functions:
        generateFunction(fn)
        emitLine("")

    return output.toString()
```

---

## Full Example

```
Source:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn main() i32 {
    return 0;
}

Generated C:
    #include <stdint.h>
    #include <stdbool.h>

    int32_t add(int32_t p0, int32_t p1);
    int32_t main();

    int32_t add(int32_t p0, int32_t p1) {
        int32_t t0 = p0;
        int32_t t1 = p1;
        int32_t t2 = t0 + t1;
        return t2;
    }

    int32_t main() {
        int32_t t0 = 0;
        return t0;
    }
```

---

## Compilation

Save output to a file and compile:

```bash
# Save generated code
./my_compiler source.mini > output.c

# Compile with C compiler
cc output.c -o program

# Run
./program
echo $?   # Shows return value
```

---

## With Optimization

```bash
# Debug build (for readable assembly)
cc -g output.c -o program

# Optimized build
cc -O2 output.c -o program

# Maximum optimization
cc -O3 output.c -o program
```

---

## Main Function

Most C programs need `main` to return `int` (not `int32_t`):

```
// Our convention: main always returns i32 (maps to int32_t)
// This is compatible with C's int on most platforms
```

If strict compliance needed:

```
function generateMainWrapper():
    emitLine("int main(void) {")
    emitLine("    return (int)program_main();")
    emitLine("}")
```

Where `program_main` is the user's main function renamed.

---

## Minimal Output

For the simplest program:

```
Source:
fn main() i32 {
    return 42;
}

Generated C:
    #include <stdint.h>
    #include <stdbool.h>

    int32_t main() {
        int32_t t0 = 42;
        return t0;
    }
```

Test:
```bash
cc output.c -o test && ./test && echo $?
# Output: 42
```

---

## Verify Your Implementation

### Test 1: Single function
```
Input:
    fn main() i32 { return 0; }

Output includes:
    #include <stdint.h>
    #include <stdbool.h>
    int32_t main() { ... }
```

### Test 2: Multiple functions
```
Input:
    fn helper() i32 { return 1; }
    fn main() i32 { return 0; }

Output includes both functions in order
```

### Test 3: Compilable output
```
Generated output compiles with: cc output.c -o test
```

### Test 4: Correct execution
```
fn main() i32 { return 42; }

After compilation, ./test returns exit code 42
```

---

## What's Next

Let's put together the complete code generator.

Next: [Lesson 5.10: Complete Codegen](../10-putting-together/) →
