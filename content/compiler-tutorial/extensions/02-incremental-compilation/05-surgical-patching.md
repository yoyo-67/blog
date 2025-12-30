---
title: "Module 5: Surgical Patching"
weight: 5
---

# Module 5: Surgical Patching

When the combined hash changes (a dependency was modified), you can't use the cached output directly. But do you really need to recompile ALL files? No! **Surgical patching** lets you recompile only the changed files and patch them into the cached output.

**What you'll build:**
- File markers to identify sections in combined output
- Parser to extract cached sections
- Change detector to find what differs
- Surgical assembly to mix cached and fresh sections
- Heuristics to decide when to patch vs rebuild

---

## Sub-lesson 5.1: File Markers

### The Problem

Your compiler produces combined LLVM IR for all files. But when you need to update just one file's output, how do you know where it is?

```
Combined output (no markers):
─────────────────────────────
define i32 @main() { ... }
define i32 @helper() { ... }
define i32 @math_add() { ... }
define i32 @math_sub() { ... }
define i32 @util_log() { ... }

Questions:
- Which functions came from which file?
- Where does main.mini end and math.mini begin?
- If math.mini changed, what do I replace?

Answer: You can't tell! We need markers.
```

### The Solution

Embed markers before each file's section:

```
; ==== FILE: main.mini:0x123abc ====
define i32 @main() { ... }
define i32 @helper() { ... }

; ==== FILE: math.mini:0x456def ====
define i32 @math_add() { ... }
define i32 @math_sub() { ... }

; ==== FILE: utils.mini:0x789abc ====
define i32 @util_log() { ... }
```

**Marker Format:**

```
MARKER = "; ==== FILE: {path}:{hash} ====\n"

Components:
- "; ==== FILE: " - Fixed prefix (easy to search)
- path           - File path (for identification)
- ":"            - Separator
- hash           - Combined hash in hex (for change detection)
- " ===="        - Fixed suffix
- "\n"           - Newline

Example:
"; ==== FILE: lib/math.mini:0x3db3b7314a73226b ====\n"
```

**Why Include the Hash?**

Without hash:
```
; ==== FILE: math.mini ====
```
We'd need to look up the hash separately. Extra work, extra bugs.

With hash:
```
; ==== FILE: math.mini:0x456def ====
```
Everything we need is right there. Self-contained.

**Generate Output with Markers:**

```
FILE_MARKER_PREFIX = "; ==== FILE: "
FILE_MARKER_SUFFIX = " ===="

formatMarker(path, hash) -> string {
    return format("{}{}:0x{:016x}{}\n",
        FILE_MARKER_PREFIX,
        path,
        hash,
        FILE_MARKER_SUFFIX)
}

generateWithMarkers(files) -> string {
    output = []

    for file in files {
        // Add marker
        marker = formatMarker(file.path, file.combined_hash)
        output.append(marker)

        // Add file's LLVM IR
        output.append(file.llvm_ir)
        output.append("\n")
    }

    return join(output, "")
}
```

### Try It Yourself

1. Define `FILE_MARKER_PREFIX` and `FILE_MARKER_SUFFIX` constants
2. Implement `formatMarker()`
3. Implement `generateWithMarkers()`
4. Test:

```
// Test: Marker generation
marker = formatMarker("test.mini", 0x123456789abcdef0)
assert marker == "; ==== FILE: test.mini:0x123456789abcdef0 ====\n"

// Test: Combined output
files = [
    { path: "a.mini", combined_hash: 0x111, llvm_ir: "define @a() {}" },
    { path: "b.mini", combined_hash: 0x222, llvm_ir: "define @b() {}" },
]
output = generateWithMarkers(files)

assert output.contains("; ==== FILE: a.mini:")
assert output.contains("; ==== FILE: b.mini:")
assert output.contains("define @a()")
assert output.contains("define @b()")
```

---

## Sub-lesson 5.2: Parse Cached Sections

### The Problem

You have cached combined output with markers. Now you need to extract individual file sections so you can keep some and replace others.

```
Cached output:
; ==== FILE: a.mini:0x111 ====
content A
; ==== FILE: b.mini:0x222 ====
content B
; ==== FILE: c.mini:0x333 ====
content C

Goal: Extract into:
[
    { path: "a.mini", hash: 0x111, content: "content A\n" },
    { path: "b.mini", hash: 0x222, content: "content B\n" },
    { path: "c.mini", hash: 0x333, content: "content C\n" },
]
```

### The Solution

Parse the cached output line by line, splitting on markers.

**Data Structure:**

```
FileSection {
    path: string       // File path from marker
    hash: u64          // Combined hash from marker
    content: string    // Everything between this marker and the next
}
```

**Parser Implementation:**

```
parseCachedSections(cached_ir) -> []FileSection {
    sections = []
    current_section = null
    content_builder = []

    for line in cached_ir.lines() {
        if line.startsWith(FILE_MARKER_PREFIX) {
            // Found a marker - save previous section if exists
            if current_section != null {
                current_section.content = join(content_builder, "\n")
                sections.append(current_section)
                content_builder = []
            }

            // Parse this marker
            current_section = parseMarker(line)
        } else {
            // Regular content line
            if current_section != null {
                content_builder.append(line)
            }
        }
    }

    // Don't forget the last section!
    if current_section != null {
        current_section.content = join(content_builder, "\n")
        sections.append(current_section)
    }

    return sections
}

parseMarker(line) -> FileSection {
    // Line: "; ==== FILE: path/to/file.mini:0x123456789abcdef0 ===="

    // Remove prefix and suffix
    inner = line[FILE_MARKER_PREFIX.len .. line.len - FILE_MARKER_SUFFIX.len]

    // inner = "path/to/file.mini:0x123456789abcdef0"

    // Find the hash separator (last colon, since path may contain colons)
    colon_pos = inner.lastIndexOf(':')

    path = inner[0 .. colon_pos]
    hash_str = inner[colon_pos + 1 ..]

    // Parse hex hash (skip "0x" prefix if present)
    if hash_str.startsWith("0x") {
        hash_str = hash_str[2..]
    }
    hash = parseHexToU64(hash_str)

    return FileSection {
        path: path,
        hash: hash,
        content: "",  // Filled in later
    }
}
```

### Try It Yourself

1. Implement `parseMarker()`
2. Implement `parseCachedSections()`
3. Test:

```
// Test: Single section
cached = """
; ==== FILE: test.mini:0x0000000000000123 ====
define i32 @test() {
    ret i32 42
}
"""

sections = parseCachedSections(cached)
assert sections.len == 1
assert sections[0].path == "test.mini"
assert sections[0].hash == 0x123
assert sections[0].content.contains("ret i32 42")

// Test: Multiple sections
cached = """
; ==== FILE: a.mini:0x111 ====
content A

; ==== FILE: b.mini:0x222 ====
content B
"""

sections = parseCachedSections(cached)
assert sections.len == 2
assert sections[0].path == "a.mini"
assert sections[1].path == "b.mini"
assert sections[0].content.contains("content A")
assert sections[1].content.contains("content B")
```

---

## Sub-lesson 5.3: Detect Changed Files

### The Problem

You have:
1. Cached sections with their hashes
2. Current files with their new combined hashes

Which files changed? Which can we reuse?

```
Cached sections:          Current files:
a.mini:0x111              a.mini → hash 0x111  (same)
b.mini:0x222              b.mini → hash 0x999  (CHANGED!)
c.mini:0x333              c.mini → hash 0x333  (same)
                          d.mini → hash 0x444  (NEW!)
```

### The Solution

Compare hashes to categorize files:

```
┌─────────────────────────────────────────────────────────────────────┐
│ FILE CATEGORIES                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ UNCHANGED: cached hash == current hash                              │
│   → Use cached section directly                                     │
│                                                                     │
│ CHANGED: cached hash != current hash                                │
│   → Recompile this file                                             │
│                                                                     │
│ NEW: Not in cache                                                   │
│   → Compile this file (first time)                                  │
│                                                                     │
│ REMOVED: In cache but not in current files                          │
│   → Don't include in output                                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Data Structure:**

```
Changes {
    unchanged: []FileSection    // From cache, hash matched
    changed: []FilePath         // Need to recompile
    new_files: []FilePath       // Not in cache
}
```

**Detection Implementation:**

```
detectChanges(cached_sections, current_files) -> Changes {
    changes = Changes {
        unchanged: [],
        changed: [],
        new_files: [],
    }

    // Build lookup map for cached sections
    cached_by_path = Map<string, FileSection>{}
    for section in cached_sections {
        cached_by_path.put(section.path, section)
    }

    // Categorize each current file
    for file in current_files {
        if cached_by_path.get(file.path) -> cached_section {
            // File exists in cache
            if cached_section.hash == file.combined_hash {
                // Hash matches - unchanged!
                changes.unchanged.append(cached_section)
            } else {
                // Hash differs - changed
                changes.changed.append(file.path)
            }
        } else {
            // Not in cache - new file
            changes.new_files.append(file.path)
        }
    }

    return changes
}
```

### Try It Yourself

1. Implement `detectChanges()`
2. Test all categories:

```
// Setup
cached_sections = [
    { path: "a.mini", hash: 0x111, content: "..." },
    { path: "b.mini", hash: 0x222, content: "..." },
    { path: "c.mini", hash: 0x333, content: "..." },
]

current_files = [
    { path: "a.mini", combined_hash: 0x111 },  // Unchanged
    { path: "b.mini", combined_hash: 0x999 },  // Changed
    { path: "d.mini", combined_hash: 0x444 },  // New
    // c.mini removed
]

changes = detectChanges(cached_sections, current_files)

assert changes.unchanged.len == 1
assert changes.unchanged[0].path == "a.mini"

assert changes.changed.len == 1
assert changes.changed[0] == "b.mini"

assert changes.new_files.len == 1
assert changes.new_files[0] == "d.mini"
```

### Benchmark Data

| Operation | Time (10K files) |
|-----------|-----------------|
| Parse cached sections | ~50ms |
| Detect changes | ~1ms |
| **Total detection** | **~51ms** |

The overhead is minimal compared to recompiling everything.

---

## Sub-lesson 5.4: Surgical Assembly

### The Problem

You have:
- Unchanged sections from cache
- Newly compiled files

How do you combine them into a single output while preserving the correct order?

```
Desired output order:
1. main.mini (changed → use new)
2. math.mini (unchanged → use cached)
3. utils.mini (unchanged → use cached)
4. config.mini (new → use new)
```

### The Solution

Iterate through current files in order, choosing cached or new content for each.

**Implementation:**

```
surgicalAssemble(
    current_files,     // All files in order
    cached_sections,   // Parsed from cache
    compiled_files,    // Freshly compiled Map<path, {llvm_ir, combined_hash}>
) -> string {
    output = []

    // Build lookup for cached sections
    cached_by_path = Map<string, FileSection>{}
    for section in cached_sections {
        cached_by_path.put(section.path, section)
    }

    for file in current_files {
        if compiled_files.get(file.path) -> compiled {
            // This file was recompiled - use new version
            marker = formatMarker(file.path, compiled.combined_hash)
            output.append(marker)
            output.append(compiled.llvm_ir)
            output.append("\n")
        } else if cached_by_path.get(file.path) -> cached {
            // This file unchanged - use cached section
            marker = formatMarker(cached.path, cached.hash)
            output.append(marker)
            output.append(cached.content)
            // Note: cached.content already has trailing newline
        } else {
            // This shouldn't happen if detectChanges was used correctly
            error("File not found in cache or compiled: {}", file.path)
        }
    }

    return join(output, "")
}
```

**Complete Surgical Patch Flow:**

```
surgicalPatch(cache, current_files, verbose) -> string | null {
    // 1. Get cached output
    cached_ir = cache.zir_cache.getCombinedIr("main")
    if cached_ir == null {
        return null  // No cache, can't patch
    }

    // 2. Parse cached sections
    cached_sections = parseCachedSections(cached_ir)
    if cached_sections.len == 0 {
        return null  // Cache corrupted
    }

    // 3. Detect changes
    changes = detectChanges(cached_sections, current_files)

    if verbose {
        print("[surgical] {} unchanged, {} changed, {} new",
            changes.unchanged.len,
            changes.changed.len,
            changes.new_files.len)
    }

    // 4. Compile only changed/new files
    compiled_files = Map<string, CompiledFile>{}

    for path in changes.changed {
        source = read_file(path)
        ir = compileFile(source)
        hash = computeCombinedHash(cache.hash_cache, path)
        compiled_files.put(path, { llvm_ir: ir, combined_hash: hash })
    }

    for path in changes.new_files {
        source = read_file(path)
        ir = compileFile(source)
        hash = computeCombinedHash(cache.hash_cache, path)
        compiled_files.put(path, { llvm_ir: ir, combined_hash: hash })
    }

    // 5. Assemble output
    output = surgicalAssemble(current_files, cached_sections, compiled_files)

    // 6. Update cache
    cache.zir_cache.putCombinedIr("main", output)

    return output
}
```

### Try It Yourself

1. Implement `surgicalAssemble()`
2. Implement `surgicalPatch()`
3. Test:

```
// Setup: Cache has a.mini and b.mini
cache.zir_cache.putCombinedIr("main", """
; ==== FILE: a.mini:0x111 ====
define @a() { original_a }

; ==== FILE: b.mini:0x222 ====
define @b() { original_b }
""")

// Current: a.mini unchanged, b.mini changed
current_files = [
    { path: "a.mini", combined_hash: 0x111 },
    { path: "b.mini", combined_hash: 0x999 },
]

// b.mini has new content
compiled_b = { llvm_ir: "define @b() { new_b }", combined_hash: 0x999 }

output = surgicalPatch(cache, current_files, verbose: true)
// Output: [surgical] 1 unchanged, 1 changed, 0 new

assert output.contains("original_a")  // From cache
assert output.contains("new_b")       // Freshly compiled
assert not output.contains("original_b")
```

### Benchmark Data

| Scenario | Full Rebuild | Surgical Patch | Speedup |
|----------|-------------|----------------|---------|
| 10 files, 1 changed | 50ms | 10ms | **5x** |
| 100 files, 1 changed | 500ms | 15ms | **33x** |
| 1000 files, 1 changed | 5000ms | 25ms | **200x** |

The more files you have, the bigger the win!

---

## Sub-lesson 5.5: Decision Heuristics

### The Problem

Surgical patching isn't always the best choice:
- No cached output? Can't patch.
- 90% of files changed? Full rebuild is simpler.
- Cache is stale/corrupted? Don't trust it.

### The Solution

Use heuristics to decide: patch or rebuild?

```
┌─────────────────────────────────────────────────────────────────────┐
│ DECISION HEURISTICS                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ USE SURGICAL PATCHING when:                                         │
│   ✓ Cached output exists                                            │
│   ✓ Cache covers most files (>50%)                                  │
│   ✓ Few files changed (<50%)                                        │
│   ✓ Change count is manageable (<100 files)                         │
│                                                                     │
│ FALL BACK TO FULL REBUILD when:                                     │
│   ✗ No cached output                                                │
│   ✗ Cache coverage too low (<50%)                                   │
│   ✗ Too many files changed (>50%)                                   │
│   ✗ Too many total changes (>100 files)                             │
│   ✗ Parsing cached output failed                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
shouldUseSurgicalPatch(
    cached_sections_count,
    total_files_count,
    changed_count,
    new_count
) -> bool {
    // No cache? Can't patch
    if cached_sections_count == 0 {
        return false
    }

    // Calculate ratios
    total_changes = changed_count + new_count
    coverage_ratio = cached_sections_count / total_files_count
    change_ratio = total_changes / total_files_count

    // Too many changes? Full rebuild
    if total_changes > 100 {
        return false
    }

    // Low cache coverage? Full rebuild
    if coverage_ratio < 0.5 {
        return false
    }

    // Most files changed? Full rebuild
    if change_ratio > 0.5 {
        return false
    }

    // All checks passed - surgical patch!
    return true
}
```

**Integrate with Build:**

```
incrementalBuildWithPatching(cache, entry_path, verbose) -> string {
    // Collect all files to compile
    current_files = collectFilesRecursive(cache.hash_cache, entry_path)

    // Try surgical patch first
    if cache.zir_cache.getCombinedIr(entry_path) != null {
        cached_sections = parseCachedSections(
            cache.zir_cache.getCombinedIr(entry_path)
        )
        changes = detectChanges(cached_sections, current_files)

        if shouldUseSurgicalPatch(
            cached_sections.len,
            current_files.len,
            changes.changed.len,
            changes.new_files.len
        ) {
            if verbose {
                print("[strategy] Surgical patch: {} cached, {} to compile",
                    changes.unchanged.len,
                    changes.changed.len + changes.new_files.len)
            }
            return surgicalPatch(cache, current_files, verbose)
        } else {
            if verbose {
                print("[strategy] Full rebuild: {} files",
                    current_files.len)
            }
        }
    }

    // Full rebuild (with function-level caching)
    return fullBuildWithMarkers(cache, current_files, verbose)
}
```

### Logging for Debugging

Good logging helps understand what the compiler is doing:

```
Example output for different scenarios:

# Scenario 1: Clean cache (first build)
[strategy] Full rebuild: 100 files
[build] Compiled 100 files in 500ms

# Scenario 2: Nothing changed
[fast-path] Nothing changed, using cached output

# Scenario 3: One file changed
[strategy] Surgical patch: 99 cached, 1 to compile
[surgical] Compiling: math.mini
[build] Surgical patch complete in 15ms

# Scenario 4: Many files changed
[strategy] Full rebuild: 100 files (60 changed, exceeds threshold)
[build] Compiled 100 files in 500ms
```

### Try It Yourself

1. Implement `shouldUseSurgicalPatch()`
2. Integrate with your build function
3. Test all scenarios:

```
// Test: Use surgical patch
assert shouldUseSurgicalPatch(
    cached_sections_count: 100,
    total_files_count: 100,
    changed_count: 2,
    new_count: 0
) == true

// Test: Full rebuild - no cache
assert shouldUseSurgicalPatch(
    cached_sections_count: 0,
    total_files_count: 100,
    changed_count: 2,
    new_count: 0
) == false

// Test: Full rebuild - too many changes
assert shouldUseSurgicalPatch(
    cached_sections_count: 100,
    total_files_count: 100,
    changed_count: 60,
    new_count: 0
) == false

// Test: Full rebuild - low coverage
assert shouldUseSurgicalPatch(
    cached_sections_count: 30,
    total_files_count: 100,
    changed_count: 2,
    new_count: 0
) == false
```

---

## Summary: Complete Surgical Patching

```
┌────────────────────────────────────────────────────────────────────┐
│ SURGICAL PATCHING FLOW                                             │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ 1. Load cached combined IR                                         │
│    └── Contains file markers: "; ==== FILE: path:hash ===="        │
│                                                                    │
│ 2. Parse into sections                                             │
│    └── Extract path, hash, content for each file                   │
│                                                                    │
│ 3. Detect changes                                                  │
│    └── Compare cached hashes with current combined hashes          │
│    └── Categorize: unchanged, changed, new                         │
│                                                                    │
│ 4. Decide strategy                                                 │
│    └── Use heuristics: coverage, change ratio, absolute count      │
│                                                                    │
│ 5. Compile only what changed                                       │
│    └── Changed files: recompile                                    │
│    └── New files: compile for first time                           │
│                                                                    │
│ 6. Assemble output                                                 │
│    └── Mix cached sections with freshly compiled                   │
│    └── Preserve file order                                         │
│                                                                    │
│ 7. Update cache                                                    │
│    └── Store new combined IR for next build                        │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Performance Summary:**

| Technique | When It Helps | Typical Speedup |
|-----------|---------------|-----------------|
| File markers | Always (enables patching) | - |
| Surgical patch | 1-10 files changed | 10-100x |
| Heuristics | Many files changed | Avoids slow path |

---

## Next Steps

You now have a complete incremental compilation system:
- Change detection with mtime optimization
- Multi-level caching (file and function)
- Surgical patching for minimal recompilation

But is it fast enough for 10K+ files? Let's optimize!

**Next: [Module 6: Performance](../06-performance/)** - Make it fast at scale

---

## Complete Code Reference

For a complete implementation, see:
- `src/main.zig` - `surgicalPatch()`, `parseCachedSections()`

Key patterns:
- Marker format: `; ==== FILE: path:hash ====`
- Section parsing with state machine
- Hash comparison for change detection
- Heuristic-based strategy selection
