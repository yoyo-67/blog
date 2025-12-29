---
title: "2.5: Surgical Patching"
weight: 5
---

# Lesson 2.5: Surgical Patching

File-level and function-level caches are great, but there's an even more powerful technique: **surgical patching**. Instead of recompiling entire files, we can patch only the changed sections of the output.

---

## Goal

Implement surgical patching that:
- Embeds file markers in the combined LLVM IR output
- Parses cached output to identify sections by file
- Replaces only changed sections while keeping unchanged ones
- Falls back to full rebuild when patching isn't efficient

---

## The Concept

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SURGICAL PATCHING                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Combined LLVM IR with file markers:                                        │
│                                                                              │
│   ; ==== FILE: main.mini:0x123abc ====                                       │
│   define i32 @main() {                                                       │
│       ...                                                                    │
│   }                                                                          │
│                                                                              │
│   ; ==== FILE: math.mini:0x456def ====                                       │
│   define i32 @math_add(i32 %0, i32 %1) {                                    │
│       ...                                                                    │
│   }                                                                          │
│                                                                              │
│   ; ==== FILE: utils.mini:0x789abc ====                                      │
│   define i32 @utils_helper() {                                              │
│       ...                                                                    │
│   }                                                                          │
│                                                                              │
│   If only math.mini changed:                                                 │
│   - Keep main.mini section (hash unchanged)                                  │
│   - REPLACE math.mini section (hash changed)                                 │
│   - Keep utils.mini section (hash unchanged)                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Surgical Patching?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         COMPARISON                                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   WITHOUT surgical patching (file cache miss):                               │
│   ──────────────────────────────────────────                                 │
│   One file changed → recompile ALL files → regenerate entire output          │
│                                                                              │
│   WITH surgical patching:                                                     │
│   ──────────────────────                                                     │
│   One file changed → recompile ONLY that file → patch into cached output     │
│                                                                              │
│   10 files, 1 changed:                                                       │
│   Without: Compile 10 files                                                  │
│   With:    Compile 1 file + patch                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## File Marker Format

```
FILE_MARKER_PREFIX = "; ==== FILE: "
FILE_MARKER_SUFFIX = " ====\n"

// Full marker format:
// ; ==== FILE: path/to/file.mini:0x123456789abcdef ====
//              ^--- file path ---^ ^--- hash -------^
```

The marker contains:
- File path (for identification)
- Combined hash (for change detection)

---

## Step 1: Generate Output with Markers

When compiling, embed markers before each file's section:

```
generateWithMarkers(files) -> string {
    output = []

    for file in files {
        // Add file marker
        marker = format("{}{}:0x{:016x}{}",
            FILE_MARKER_PREFIX,
            file.path,
            file.combined_hash,
            FILE_MARKER_SUFFIX)

        output.append(marker)

        // Add file's LLVM IR
        output.append(file.llvm_ir)
        output.append("\n")
    }

    return join(output, "")
}
```

Example output:
```llvm
; ==== FILE: main.mini:0x3db3b7314a73226b ====
define i32 @main() {
    %1 = call i32 @math_add(i32 1, i32 2)
    ret i32 %1
}

; ==== FILE: math.mini:0x9a2eb98b6d927e93 ====
define i32 @math_add(i32 %0, i32 %1) {
    %3 = add i32 %0, %1
    ret i32 %3
}
```

---

## Step 2: Parse Cached Output

Parse the cached combined IR to extract sections:

```
FileSection {
    path:    string,
    hash:    u64,
    content: string,
}

parseCachedOutput(cached_ir) -> []FileSection {
    sections = []
    current_section = null

    for line in cached_ir.lines() {
        if line.startsWith(FILE_MARKER_PREFIX) {
            // Save previous section
            if current_section != null {
                sections.append(current_section)
            }

            // Parse marker: "; ==== FILE: path:0xhash ===="
            marker_content = line[FILE_MARKER_PREFIX.len..]
            marker_content = marker_content[..marker_content.len - FILE_MARKER_SUFFIX.len]

            // Split on last ":"
            colon_pos = marker_content.lastIndexOf(':')
            path = marker_content[0..colon_pos]
            hash_str = marker_content[colon_pos+1..]
            hash = parseHex(hash_str)

            current_section = FileSection {
                path: path,
                hash: hash,
                content: "",
            }
        } else if current_section != null {
            // Add line to current section
            current_section.content += line + "\n"
        }
    }

    // Don't forget last section
    if current_section != null {
        sections.append(current_section)
    }

    return sections
}
```

---

## Step 3: Identify Changed Files

Compare cached sections with current file hashes:

```
identifyChanges(cached_sections, current_files) -> Changes {
    changed = []
    unchanged = []

    for file in current_files {
        found = false

        for section in cached_sections {
            if section.path == file.path {
                found = true
                if section.hash == file.combined_hash {
                    unchanged.append(section)
                } else {
                    changed.append(file)
                }
                break
            }
        }

        if not found {
            // New file - needs compilation
            changed.append(file)
        }
    }

    return Changes { changed, unchanged }
}
```

---

## Step 4: Surgical Patch

Assemble the output from cached sections + recompiled sections:

```
surgicalPatch(cached_sections, current_files, changed_files) -> string {
    output = []

    for file in current_files {
        // Check if this file was recompiled
        if file in changed_files {
            // Use freshly compiled IR
            marker = formatMarker(file.path, file.combined_hash)
            output.append(marker)
            output.append(file.llvm_ir)
        } else {
            // Use cached section
            for section in cached_sections {
                if section.path == file.path {
                    marker = formatMarker(section.path, section.hash)
                    output.append(marker)
                    output.append(section.content)
                    break
                }
            }
        }
    }

    return join(output, "")
}
```

---

## Step 5: Fallback Heuristics

Surgical patching isn't always the best choice. Use heuristics to decide:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         FALLBACK CONDITIONS                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Use surgical patching when:                                                │
│   • Few files changed (<50% of total)                                        │
│   • Cache has good coverage (>50% of files)                                  │
│   • Number of changes is manageable (<100 files)                             │
│                                                                              │
│   Fall back to full rebuild when:                                            │
│   • Too many files changed (>50% of total)                                   │
│   • Cache coverage is poor (<50% of files)                                   │
│   • Too many changes to track (>100 files)                                   │
│   • No cached output available                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

```
shouldUseSurgicalPatch(changes, total_files, cached_sections) -> bool {
    // No cached output? Full rebuild
    if cached_sections.len == 0 {
        return false
    }

    // Too many changes? Full rebuild
    if changes.changed.len > 100 {
        return false
    }

    // Calculate coverage
    coverage = cached_sections.len / total_files
    change_ratio = changes.changed.len / total_files

    // Low coverage? Full rebuild
    if coverage < 0.5 {
        return false
    }

    // Most files changed? Full rebuild
    if change_ratio > 0.5 {
        return false
    }

    return true
}
```

---

## Complete Surgical Patch Flow

```
incrementalBuildWithPatching(files, cache) -> string {
    // Load cached combined IR
    cached_ir = cache.getCombinedIr()

    if cached_ir == null {
        // No cache - full build with markers
        return fullBuildWithMarkers(files, cache)
    }

    // Parse cached output
    cached_sections = parseCachedOutput(cached_ir)

    // Compute current hashes
    for file in files {
        file.combined_hash = computeCombinedHash(file)
    }

    // Identify changes
    changes = identifyChanges(cached_sections, files)

    // Decide strategy
    if not shouldUseSurgicalPatch(changes, files.len, cached_sections) {
        return fullBuildWithMarkers(files, cache)
    }

    // Compile only changed files
    for file in changes.changed {
        file.llvm_ir = compileFile(file)
    }

    // Assemble patched output
    output = surgicalPatch(cached_sections, files, changes.changed)

    // Save for next time
    cache.putCombinedIr(output)

    return output
}
```

---

## Example: Surgical Patch in Action

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         SURGICAL PATCH EXAMPLE                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Files: main.mini, math.mini, utils.mini, io.mini, config.mini              │
│   You modified: math.mini                                                    │
│                                                                              │
│   1. Load cached combined IR (contains all 5 files with markers)             │
│                                                                              │
│   2. Parse sections:                                                         │
│      main.mini:0x111...  [cached content]                                    │
│      math.mini:0x222...  [cached content]  ← hash will differ                │
│      utils.mini:0x333... [cached content]                                    │
│      io.mini:0x444...    [cached content]                                    │
│      config.mini:0x555...[cached content]                                    │
│                                                                              │
│   3. Compute current hashes:                                                 │
│      main.mini:0x111...  MATCH                                               │
│      math.mini:0x999...  CHANGED!                                            │
│      utils.mini:0x333... MATCH                                               │
│      io.mini:0x444...    MATCH                                               │
│      config.mini:0x555...MATCH                                               │
│                                                                              │
│   4. Compile only math.mini                                                  │
│                                                                              │
│   5. Assemble output:                                                        │
│      main.mini   → use cached section                                        │
│      math.mini   → use newly compiled IR                                     │
│      utils.mini  → use cached section                                        │
│      io.mini     → use cached section                                        │
│      config.mini → use cached section                                        │
│                                                                              │
│   Result: 1/5 files compiled (80% savings!)                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Implementation

### Test 1: Generate markers
```
file = { path: "test.mini", combined_hash: 0x123456, llvm_ir: "define..." }
output = generateWithMarkers([file])

Check: output.contains("; ==== FILE: test.mini:0x0000000000123456 ====")
```

### Test 2: Parse markers
```
ir = '''
; ==== FILE: a.mini:0x111 ====
define @a() {}

; ==== FILE: b.mini:0x222 ====
define @b() {}
'''

sections = parseCachedOutput(ir)

Check: sections.len == 2
Check: sections[0].path == "a.mini"
Check: sections[0].hash == 0x111
Check: sections[1].path == "b.mini"
Check: sections[1].hash == 0x222
```

### Test 3: Identify changes
```
cached = [
    { path: "a.mini", hash: 0x111 },
    { path: "b.mini", hash: 0x222 },
]

current = [
    { path: "a.mini", combined_hash: 0x111 },  // unchanged
    { path: "b.mini", combined_hash: 0x999 },  // changed
]

changes = identifyChanges(cached, current)

Check: changes.unchanged.len == 1
Check: changes.changed.len == 1
Check: changes.changed[0].path == "b.mini"
```

### Test 4: Surgical patch
```
// Cached: a.mini and b.mini
cached_sections = parseCachedOutput(cached_ir)

// Current: a.mini unchanged, b.mini changed
current_files = [a_file, b_file_new]
changed = [b_file_new]

output = surgicalPatch(cached_sections, current_files, changed)

Check: output.contains("a.mini")  // from cache
Check: output.contains(b_file_new.llvm_ir)  // freshly compiled
```

---

## What's Next

Now let's put everything together into a complete multi-level cache system.

Next: [Lesson 2.6: Multi-Level Cache](../06-multi-level-cache/) →
