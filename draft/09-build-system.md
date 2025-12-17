---
title: "Part 9: The Build System (build.zig)"
---

# Part 9: The Build System (build.zig)

In this article, we'll explore Zig's unique build system. Unlike traditional build tools, Zig's build system is written in Zig itself - using comptime to create a type-safe, debuggable, cross-platform build experience.

---

## Part 1: Why Do We Need a Build System?

### The Problem

Compiling a single file is easy:

```bash
zig build-exe main.zig
```

But real projects have many challenges:

```
┌─────────────────────────────────────────────────────────────┐
│                    REAL PROJECT CHALLENGES                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. MULTIPLE FILES                                           │
│     main.zig, utils.zig, network.zig, database.zig...       │
│     How do they fit together?                                │
│                                                              │
│  2. DEPENDENCIES                                             │
│     Your code uses external libraries                        │
│     Those libraries have their own dependencies...           │
│                                                              │
│  3. DIFFERENT TARGETS                                        │
│     Build for Linux, Windows, macOS                          │
│     Build for x86, ARM, WASM                                 │
│                                                              │
│  4. BUILD CONFIGURATIONS                                     │
│     Debug build (slow, with symbols)                         │
│     Release build (fast, optimized)                          │
│                                                              │
│  5. CUSTOM STEPS                                             │
│     Generate code, run tests, package artifacts              │
│     Copy assets, generate documentation                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Traditional Build Systems

**Makefiles:**
```makefile
CC = gcc
CFLAGS = -Wall -O2
OBJECTS = main.o utils.o network.o

program: $(OBJECTS)
    $(CC) $(CFLAGS) -o $@ $^

%.o: %.c
    $(CC) $(CFLAGS) -c -o $@ $<

clean:
    rm -f $(OBJECTS) program
```

Problems:
- Separate language (not your programming language)
- Tab vs spaces matters (really!)
- Hard to debug
- Platform-specific (Windows?)
- No type checking

**CMake:**
```cmake
cmake_minimum_required(VERSION 3.10)
project(MyProject)
add_executable(program main.c utils.c network.c)
target_compile_options(program PRIVATE -Wall -O2)
```

Problems:
- Another language to learn
- Generates Makefiles (adds complexity)
- Confusing syntax and scoping rules
- Hard to debug

```
┌─────────────────────────────────────────────────────────────┐
│           THE FUNDAMENTAL PROBLEM                            │
│                                                              │
│  You're using LANGUAGE A to build code written in LANGUAGE B │
│                                                              │
│  - Can't use your language's features                        │
│  - Can't use your language's debugger                        │
│  - Can't use your language's IDE support                     │
│  - Must learn another toolchain                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 2: What Makes Zig's Build System Different?

### The Key Insight

```
┌─────────────────────────────────────────────────────────────┐
│                    ZIG'S APPROACH                            │
│                                                              │
│  What if the build system was written in... Zig?             │
│                                                              │
│  - Use the SAME language for code and build                  │
│  - Use the SAME debugger                                     │
│  - Use the SAME IDE                                          │
│  - Use the SAME error messages                               │
│  - Leverage comptime for configuration                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### A Simple build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Get target and optimization from command line
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create an executable
    const exe = b.addExecutable(.{
        .name = "my-program",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Install the executable
    b.installArtifact(exe);
}
```

That's it! This is a complete build configuration. And it's just Zig code!

### What You Get

```
┌─────────────────────────────────────────────────────────────┐
│              BENEFITS OF ZIG BUILD SYSTEM                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  TYPE SAFETY                                                 │
│    Misspell a function name? Compile error!                  │
│    Wrong argument type? Compile error!                       │
│    No more "undefined variable" at runtime                   │
│                                                              │
│  DEBUGGABLE                                                  │
│    Set breakpoints in your build.zig                         │
│    Inspect variables                                         │
│    Step through build logic                                  │
│                                                              │
│  CROSS-PLATFORM BY DEFAULT                                   │
│    Same build.zig works on Linux, Windows, macOS             │
│    No platform-specific conditionals needed                  │
│                                                              │
│  COMPTIME POWER                                              │
│    Generate build logic at compile time                      │
│    Conditional compilation                                   │
│    Code generation                                           │
│                                                              │
│  INTEGRATED CACHING                                          │
│    Uses the same cache as the compiler (Article 8!)          │
│    Automatic incremental builds                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 3: Anatomy of a build.zig File

### The Build Object

When Zig runs your build.zig, it passes you a `*std.Build` object. This is your interface to the build system:

```zig
pub fn build(b: *std.Build) void {
    // 'b' is your Build object
    // It has everything you need
}
```

Looking at the actual source code (`std/Build.zig`), the Build struct contains:

```
┌─────────────────────────────────────────────────────────────┐
│                    THE BUILD STRUCT                          │
│                    (from std/Build.zig)                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  graph: *Graph           // Shared state, cache, zig exe     │
│  allocator: Allocator    // Memory allocation                │
│                                                              │
│  install_tls: TopLevelStep    // The "install" step          │
│  uninstall_tls: TopLevelStep  // The "uninstall" step        │
│  default_step: *Step          // What runs by default        │
│                                                              │
│  build_root: Cache.Directory  // Where build.zig lives       │
│  cache_root: Cache.Directory  // Where cache goes            │
│  install_prefix: []const u8   // Where to install            │
│                                                              │
│  modules: StringArrayHashMap(*Module)  // Named modules      │
│  available_deps: AvailableDeps         // Dependencies       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### The Graph: Shared State

```zig
// From std/Build.zig
pub const Graph = struct {
    arena: Allocator,
    cache: Cache,                        // The compilation cache
    zig_exe: [:0]const u8,               // Path to zig executable
    env_map: EnvMap,                     // Environment variables
    global_cache_root: Cache.Directory,  // Global cache location
    zig_lib_directory: Cache.Directory,  // Standard library location
    host: ResolvedTarget,                // Native target info
    // ...
};
```

The Graph is shared across all Build instances (including dependencies). It holds the cache, environment, and compiler paths.

### Creating Artifacts

The most common operations:

```zig
pub fn build(b: *std.Build) void {
    // Create a module (reusable code)
    const my_module = b.addModule("my_module", .{
        .root_source_file = b.path("src/my_module.zig"),
    });

    // Create an executable
    const exe = b.addExecutable(.{
        .name = "my-program",
        .root_source_file = b.path("src/main.zig"),
    });

    // Create a static library
    const lib = b.addStaticLibrary(.{
        .name = "my-lib",
        .root_source_file = b.path("src/lib.zig"),
    });

    // Create a shared/dynamic library
    const shared = b.addSharedLibrary(.{
        .name = "my-shared",
        .root_source_file = b.path("src/lib.zig"),
    });
}
```

---

## Part 4: Steps and the Build Graph

### What is a Step?

Everything in the build system is a **Step**. From `std/Build/Step.zig`:

```zig
// The Step struct (simplified)
id: Id,                    // What kind of step (compile, run, install...)
name: []const u8,          // Human-readable name
owner: *Build,             // Which Build created this
makeFn: MakeFn,            // Function to execute this step
dependencies: ArrayList(*Step),  // Steps that must run BEFORE this
dependants: ArrayList(*Step),    // Steps that depend on THIS step
state: State,              // precheck, running, success, failure...
```

### Step Types

From the source code, here are all the step types:

```
┌─────────────────────────────────────────────────────────────┐
│                      STEP TYPES                              │
│                  (from Step.Id enum)                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  top_level        - Named top-level steps (install, test)    │
│  compile          - Compile Zig/C/C++ code                   │
│  install_artifact - Copy artifact to install directory       │
│  install_file     - Copy a single file                       │
│  install_dir      - Copy a directory                         │
│  remove_dir       - Remove a directory                       │
│  run              - Run an executable                        │
│  write_file       - Generate a file with content             │
│  translate_c      - Convert C headers to Zig                 │
│  config_header    - Generate config.h style headers          │
│  objcopy          - Transform object files                   │
│  fmt              - Format source code                       │
│  check_file       - Verify file contents                     │
│  check_object     - Verify object file properties            │
│  options          - Generate options module                  │
│  fail             - Always fail (for testing)                │
│  custom           - User-defined step                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### The Build Graph

Steps form a **directed acyclic graph (DAG)**:

```
┌─────────────────────────────────────────────────────────────┐
│                    BUILD GRAPH EXAMPLE                       │
│                                                              │
│     ┌─────────────┐                                          │
│     │   install   │  (default step)                          │
│     └──────┬──────┘                                          │
│            │                                                 │
│            ▼                                                 │
│     ┌─────────────┐                                          │
│     │  install    │                                          │
│     │  artifact   │                                          │
│     └──────┬──────┘                                          │
│            │                                                 │
│            ▼                                                 │
│     ┌─────────────┐     ┌─────────────┐                      │
│     │   compile   │────►│   compile   │                      │
│     │   (exe)     │     │   (lib)     │                      │
│     └─────────────┘     └─────────────┘                      │
│                                                              │
│  Arrow means "depends on"                                    │
│  Steps run in dependency order                               │
│  Independent steps can run in PARALLEL                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Creating Dependencies

```zig
pub fn build(b: *std.Build) void {
    // Create steps
    const lib = b.addStaticLibrary(.{
        .name = "mylib",
        .root_source_file = b.path("src/lib.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = b.path("src/main.zig"),
    });

    // exe depends on lib
    exe.linkLibrary(lib);

    // Create a run step
    const run_cmd = b.addRunArtifact(exe);

    // Make "zig build run" work
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
```

### Lazy Evaluation

Steps are **lazy** - they only run if needed:

```
┌─────────────────────────────────────────────────────────────┐
│                    LAZY EVALUATION                           │
│                                                              │
│  $ zig build              # Only runs "install" and deps     │
│  $ zig build run          # Only runs "run" and deps         │
│  $ zig build test         # Only runs "test" and deps        │
│                                                              │
│  Steps NOT in the dependency chain are SKIPPED!              │
│                                                              │
│  This is why `zig build` is fast even with many steps:       │
│  It only does what's actually needed.                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 5: Build Options and Configuration

### Optimization Modes

From the source code, Zig has these optimization modes:

```zig
// From std/builtin.zig
pub const OptimizeMode = enum {
    Debug,         // No optimizations, keep debug info
    ReleaseSafe,   // Optimizations ON, safety checks ON
    ReleaseFast,   // Optimizations ON, safety checks OFF (fastest)
    ReleaseSmall,  // Optimize for binary size
};
```

Using them in build.zig:

```zig
pub fn build(b: *std.Build) void {
    // Let user choose via command line
    const optimize = b.standardOptimizeOption(.{});

    // optimize is now one of: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall
    // User selects with: zig build -Doptimize=ReleaseFast
}
```

The `standardOptimizeOption` function (from Build.zig:1319):

```zig
pub fn standardOptimizeOption(b: *Build, options: StandardOptimizeOptionOptions)
    std.builtin.OptimizeMode
{
    // Check for --release flag
    if (b.option(bool, "release", "optimize for end users")) |_| {
        return options.preferred_optimize_mode orelse .ReleaseFast;
    }

    // Check for -Doptimize=X
    if (b.option(std.builtin.OptimizeMode, "optimize", "...")) |mode| {
        return mode;
    }

    // Default to Debug
    return .Debug;
}
```

### Target Selection

```zig
pub fn build(b: *std.Build) void {
    // Let user choose target via command line
    const target = b.standardTargetOptions(.{});

    // User selects with: zig build -Dtarget=x86_64-linux-gnu
    //                    zig build -Dtarget=aarch64-macos
    //                    zig build -Dtarget=wasm32-wasi
}
```

### Custom Options

You can define your own build options:

```zig
pub fn build(b: *std.Build) void {
    // Boolean option
    const enable_logging = b.option(
        bool,
        "enable-logging",
        "Enable debug logging",
    ) orelse false;

    // String option
    const config_path = b.option(
        []const u8,
        "config",
        "Path to config file",
    ) orelse "config.json";

    // Enum option
    const backend = b.option(
        enum { opengl, vulkan, metal },
        "backend",
        "Graphics backend to use",
    ) orelse .opengl;

    // Use in compilation
    const exe = b.addExecutable(.{ ... });

    // Pass options to code via @import("build_options")
    const options = b.addOptions();
    options.addOption(bool, "enable_logging", enable_logging);
    options.addOption([]const u8, "config_path", config_path);
    exe.root_module.addOptions("build_options", options);
}
```

In your Zig code:

```zig
const build_options = @import("build_options");

pub fn main() void {
    if (build_options.enable_logging) {
        std.log.info("Logging enabled!", .{});
    }
}
```

---

## Part 6: Cross-Compilation Made Simple

### Why Zig Excels at Cross-Compilation

```
┌─────────────────────────────────────────────────────────────┐
│              WHY ZIG CROSS-COMPILATION IS EASY               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. BUNDLED LIBC                                             │
│     Zig ships with libc for EVERY supported platform         │
│     No need to install cross-compilers or SDKs               │
│                                                              │
│  2. UNIFIED TOOLCHAIN                                        │
│     Same zig command for all targets                         │
│     No arm-linux-gnueabihf-gcc mess                          │
│                                                              │
│  3. TARGET TRIPLE IN CODE                                    │
│     Same build.zig for all platforms                         │
│     Just pass -Dtarget=...                                   │
│                                                              │
│  4. COMPTIME TARGET INFO                                     │
│     @import("builtin").target available at comptime          │
│     Conditional compilation without preprocessor             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Target Triples Explained

A target triple describes the platform:

```
┌─────────────────────────────────────────────────────────────┐
│                    TARGET TRIPLE FORMAT                      │
│                                                              │
│              arch - os - abi                                 │
│                                                              │
│  Examples:                                                   │
│    x86_64-linux-gnu      Linux with glibc                    │
│    x86_64-linux-musl     Linux with musl libc                │
│    aarch64-macos-none    macOS on Apple Silicon              │
│    x86_64-windows-msvc   Windows with MSVC ABI               │
│    wasm32-wasi-none      WebAssembly with WASI               │
│    arm-linux-gnueabihf   ARM Linux with hardware float       │
│                                                              │
│  Special values:                                             │
│    native                Your current system                 │
│    native-native-musl    Native arch/OS, but use musl        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Cross-Compilation in Practice

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        // Set a default different from native
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        },
    });

    const exe = b.addExecutable(.{
        .name = "my-program",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
    });

    b.installArtifact(exe);
}
```

Build for different platforms:

```bash
# Build for current system
zig build

# Build for Linux x86_64
zig build -Dtarget=x86_64-linux-gnu

# Build for Windows
zig build -Dtarget=x86_64-windows-msvc

# Build for macOS ARM
zig build -Dtarget=aarch64-macos

# Build for WebAssembly
zig build -Dtarget=wasm32-wasi

# Build for Raspberry Pi
zig build -Dtarget=arm-linux-gnueabihf
```

All with the SAME build.zig, SAME zig compiler, NO extra setup!

---

## Part 7: Dependencies and Packages

### The build.zig.zon File

Dependencies are declared in `build.zig.zon` (Zig Object Notation):

```zig
.{
    .name = "my-project",
    .version = "0.1.0",

    .dependencies = .{
        // Fetch from URL
        .zap = .{
            .url = "https://github.com/zigzap/zap/archive/v0.1.0.tar.gz",
            .hash = "1220a1b2c3d4e5f6...",
        },

        // Fetch from Git
        .mach = .{
            .url = "git+https://github.com/hexops/mach.git",
            .hash = "1220f7e8d9c0b1a2...",
        },

        // Local path (for development)
        .my_lib = .{
            .path = "../my-lib",
        },
    },

    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

### Using Dependencies in build.zig

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get a dependency
    const zap_dep = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-server",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Import a module from the dependency
    exe.root_module.addImport("zap", zap_dep.module("zap"));

    b.installArtifact(exe);
}
```

### How Dependencies Work

```
┌─────────────────────────────────────────────────────────────┐
│                  DEPENDENCY RESOLUTION                       │
│                                                              │
│  1. READ build.zig.zon                                       │
│     Parse dependency declarations                            │
│                                                              │
│  2. FETCH (if needed)                                        │
│     Download from URL or clone from Git                      │
│     Verify hash matches (security!)                          │
│     Store in global cache                                    │
│                                                              │
│  3. BUILD DEPENDENCY                                         │
│     Run dependency's build.zig                               │
│     Each dependency gets its own Build instance              │
│     (This is createChild() in Build.zig)                     │
│                                                              │
│  4. EXPOSE MODULES                                           │
│     Dependency exports modules                               │
│     Your code imports them                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

From the source (Build.zig:2006):

```zig
pub fn dependency(b: *Build, name: []const u8, args: anytype) *Dependency {
    // Look up the package hash from build.zig.zon
    const pkg_hash = findPkgHashOrFatal(b, name);

    // Find the package in the dependency cache
    // Create a child Build instance for the dependency
    // Run the dependency's build.zig
    return dependencyInner(b, name, pkg.build_root, ...);
}
```

---

## Part 8: Integration with the Compiler

### The Two-Phase Build Process

When you run `zig build`, two things happen:

```
┌─────────────────────────────────────────────────────────────┐
│                    TWO-PHASE BUILD                           │
│                                                              │
│  PHASE 1: COMPILE build.zig                                  │
│  ─────────────────────────────                               │
│    build.zig is a Zig program                                │
│    Compile it with the Zig compiler                          │
│    This produces an executable (the "build runner")          │
│                                                              │
│           build.zig                                          │
│               │                                              │
│               ▼                                              │
│        ┌───────────┐                                         │
│        │    Zig    │                                         │
│        │ Compiler  │                                         │
│        └───────────┘                                         │
│               │                                              │
│               ▼                                              │
│         build_runner                                         │
│        (executable)                                          │
│                                                              │
│  PHASE 2: RUN build_runner                                   │
│  ─────────────────────────                                   │
│    Execute the build runner                                  │
│    It calls your build() function                            │
│    It executes the build graph                               │
│                                                              │
│        build_runner                                          │
│               │                                              │
│               ▼                                              │
│    ┌─────────────────────┐                                   │
│    │  Your build() func  │                                   │
│    │  Creates steps      │                                   │
│    │  Sets up deps       │                                   │
│    └─────────────────────┘                                   │
│               │                                              │
│               ▼                                              │
│    ┌─────────────────────┐                                   │
│    │  Execute steps      │                                   │
│    │  (compile, link,    │                                   │
│    │   run tests, etc.)  │                                   │
│    └─────────────────────┘                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Caching (Connecting to Article 8)

The build system uses the SAME caching infrastructure as the compiler:

```
┌─────────────────────────────────────────────────────────────┐
│            BUILD SYSTEM + CACHING                            │
│                                                              │
│  build.zig itself is cached:                                 │
│    - First run: compile build.zig → build_runner            │
│    - Second run: build.zig unchanged? Reuse build_runner!   │
│                                                              │
│  Every compilation step is cached:                           │
│    - Hash(source + flags + deps) → cached?                   │
│    - If cached, skip compilation!                            │
│                                                              │
│  The Graph struct holds the cache:                           │
│    graph.cache: Cache   // From Build.zig                    │
│                                                              │
│  This is why `zig build` is FAST:                            │
│    - Incremental build.zig compilation                       │
│    - Incremental source compilation                          │
│    - Parallel step execution                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Step Execution

From Step.zig, steps have states:

```zig
pub const State = enum {
    precheck_unstarted,   // Not started yet
    precheck_started,     // Checking if needs to run
    precheck_done,        // Ready to run (or dirty)
    running,              // Currently executing
    dependency_failure,   // A dependency failed
    success,              // Completed successfully
    failure,              // Failed
    skipped,              // Skipped (e.g., conditional)
    skipped_oom,          // Skipped due to memory limit
};
```

The build runner:
1. Topologically sorts the step graph
2. Runs steps in dependency order
3. Runs independent steps in PARALLEL
4. Respects memory limits (`max_rss` field)

---

## Part 9: Practical Examples

### Example 1: Simple Application

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "hello",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // "zig build run" command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
```

### Example 2: Library with Tests

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The library
    const lib = b.addStaticLibrary(.{
        .name = "mylib",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Unit tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
}
```

### Example 3: C Library Integration

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "with-c",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add C source files
    exe.addCSourceFiles(.{
        .files = &.{
            "src/legacy.c",
            "src/wrapper.c",
        },
        .flags = &.{
            "-Wall",
            "-Wextra",
            "-std=c99",
        },
    });

    // Link system library
    exe.linkSystemLibrary("sqlite3");
    exe.linkLibC();

    // Add include path
    exe.addIncludePath(b.path("include"));

    b.installArtifact(exe);
}
```

### Example 4: Code Generation Step

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Generate a Zig file at build time
    const gen_step = b.addWriteFile("generated.zig",
        \\pub const version = "1.0.0";
        \\pub const build_time = @import("std").time.timestamp();
    );

    const exe = b.addExecutable(.{
        .name = "app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Use the generated file
    exe.root_module.addAnonymousImport("generated", .{
        .root_source_file = gen_step.getDirectory().path(b, "generated.zig"),
    });

    b.installArtifact(exe);
}
```

---

## Part 10: The Complete Picture

### How Everything Fits Together

```
┌─────────────────────────────────────────────────────────────┐
│                    THE COMPLETE PICTURE                      │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    build.zig.zon                      │   │
│  │               (dependency declarations)               │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                 │
│                            ▼                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                     build.zig                         │   │
│  │                  (your build logic)                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                 │
│              ┌─────────────┴─────────────┐                   │
│              │                           │                   │
│              ▼                           ▼                   │
│  ┌─────────────────────┐    ┌─────────────────────────┐     │
│  │   Phase 1: Compile  │    │    Fetch Dependencies   │     │
│  │    build.zig        │    │  (from build.zig.zon)   │     │
│  └─────────────────────┘    └─────────────────────────┘     │
│              │                           │                   │
│              └─────────────┬─────────────┘                   │
│                            │                                 │
│                            ▼                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Phase 2: Run Build Graph                 │   │
│  │                                                       │   │
│  │    ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐        │   │
│  │    │Step 1│──►│Step 2│──►│Step 3│──►│Step 4│        │   │
│  │    └──────┘   └──────┘   └──────┘   └──────┘        │   │
│  │         │                     │                       │   │
│  │         └──────────┬──────────┘                       │   │
│  │                    ▼                                  │   │
│  │              PARALLEL EXECUTION                       │   │
│  │            (where possible)                           │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                 │
│                            ▼                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 Compilation Cache                     │   │
│  │              (from Article 8)                         │   │
│  │                                                       │   │
│  │   ┌──────────────────────────────────────────────┐   │   │
│  │   │  Hash(source + flags + deps) → cached output  │   │   │
│  │   │  Skip work if already cached!                 │   │   │
│  │   └──────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────┘   │
│                            │                                 │
│                            ▼                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    Output                             │   │
│  │                                                       │   │
│  │        zig-out/                                       │   │
│  │        ├── bin/                                       │   │
│  │        │   └── my-program                             │   │
│  │        └── lib/                                       │   │
│  │            └── libmylib.a                             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### The Full Compiler Pipeline (Articles 1-9)

```
┌─────────────────────────────────────────────────────────────┐
│              ZIG COMPILATION: THE FULL PICTURE               │
│                                                              │
│                      build.zig                               │
│                          │                                   │
│                          ▼                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   BUILD SYSTEM                        │   │
│  │                   (Article 9)                         │   │
│  │   Orchestrates the entire compilation process         │   │
│  └────────────────────────┬─────────────────────────────┘   │
│                           │                                  │
│         ┌─────────────────┼─────────────────┐               │
│         │                 │                 │               │
│         ▼                 ▼                 ▼               │
│      file1.zig        file2.zig        file3.zig           │
│         │                 │                 │               │
│         ▼                 ▼                 ▼               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  FRONTEND (Articles 2-5)                             │   │
│  │  Tokenize → Parse → ZIR → Sema                       │   │
│  └─────────────────────────────────────────────────────┘   │
│         │                 │                 │               │
│         ▼                 ▼                 ▼               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  BACKEND (Article 6)                                 │   │
│  │  AIR → Machine Code                                  │   │
│  └─────────────────────────────────────────────────────┘   │
│         │                 │                 │               │
│         └─────────────────┼─────────────────┘               │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  LINKER (Article 7)                                  │   │
│  │  Combine objects → Executable                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  CACHING (Article 8)                                 │   │
│  │  Skip unchanged work                                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│                      Executable!                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Summary

Zig's build system is unique because:

1. **It's Just Zig** - No separate build language to learn
2. **Type-Safe** - Compiler catches build configuration errors
3. **Debuggable** - Use the same tools you use for regular code
4. **Cross-Platform** - Same build.zig works everywhere
5. **Integrated** - Uses the compiler's caching infrastructure
6. **Parallel** - Independent steps run concurrently
7. **Lazy** - Only runs steps that are actually needed

The build.zig file is not just configuration - it's a real program that orchestrates your build. This means you have the full power of a programming language (with comptime!) to express complex build logic.

Combined with Zig's bundled libc and unified toolchain, cross-compilation becomes trivial: just pass `-Dtarget=...` and get a working binary for any supported platform.

---

*This concludes our deep dive into the Zig compiler internals. We've covered the complete journey from source code to executable: Bootstrap → Tokenizer → Parser/AST → ZIR → Sema → AIR/CodeGen → Linking → Caching → Build System.*
