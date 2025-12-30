#!/usr/bin/env python3
"""
Generate complex .mini test files for benchmarking incremental compilation.
Creates a CONNECTED dependency tree so all files are reachable from main.mini.

- 10,000 files
- ~5,000 dependencies (all reachable from main)
"""

import os
import random
from pathlib import Path

NUM_FILES = 10000
OUTPUT_DIR = Path("tests/benchmark")

random.seed(42)


def func_name(file_idx, func_idx):
    return f"func_{file_idx}_{func_idx}"


def gen_function(name, calls=None):
    if calls:
        expr = " + ".join([f"{a}.{f}(x, y)" for a, f in calls])
    else:
        ops = ["x + y", "x * y", "x - y", "x + y + 1", "x * 2 + y"]
        expr = random.choice(ops)
    return f"fn {name}(x: i32, y: i32) i32 {{\n    return {expr};\n}}\n"


def gen_file(file_idx, imports, num_funcs=3):
    lines = []
    for path, alias, _ in imports:
        lines.append(f'import "{path}" as {alias};')
    if imports:
        lines.append("")

    for i in range(num_funcs):
        name = func_name(file_idx, i)
        calls = []
        # func_N_0 ALWAYS calls imports to ensure full tree is executed
        # Other functions randomly call imports (70% chance)
        if imports and (i == 0 or random.random() < 0.7):
            for _, alias, dep_idx in imports:  # Call ALL imports, not random sample
                calls.append((alias, func_name(dep_idx, 0)))
        lines.append(gen_function(name, calls if calls else None))

    return "\n".join(lines)


def main():
    print(f"Generating {NUM_FILES} files with connected dependency tree...")

    # Clean and create output directory
    import shutil
    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # All files in files/ subfolder
    files_dir = OUTPUT_DIR / "files"
    files_dir.mkdir(parents=True, exist_ok=True)

    files = []
    for i in range(NUM_FILES):
        files.append((i, f"files/file_{i:05d}.mini"))

    # Build a TREE structure: each file imports ~2 children
    # This ensures ALL files are reachable from main.mini
    # Layer 0: files 0-1 (roots imported by main)
    # Layer 1: files 2-5 (imported by layer 0)
    # Layer 2: files 6-13 (imported by layer 1)
    # etc. - exponential growth covers all 10K files

    deps = {i: [] for i in range(NUM_FILES)}

    # Create tree structure - each file imports up to 2 "children"
    # Children have higher indices
    total_deps = 0
    for i in range(NUM_FILES):
        # Each file can have up to 2 children
        child1 = i * 2 + 1
        child2 = i * 2 + 2

        if child1 < NUM_FILES:
            deps[i].append(child1)
            total_deps += 1
        if child2 < NUM_FILES:
            deps[i].append(child2)
            total_deps += 1

    print(f"Created {total_deps} dependency edges (binary tree)")

    # Generate all files
    for file_idx, rel_path in files:
        imports = []
        for dep_idx in deps[file_idx]:
            _, dep_path = files[dep_idx]
            # Import path relative to file location (just the filename since all in same folder)
            dep_filename = os.path.basename(dep_path)
            imports.append((dep_filename, f"m{dep_idx}", dep_idx))

        content = gen_file(file_idx, imports, random.randint(2, 4))
        (OUTPUT_DIR / rel_path).write_text(content)

        if (file_idx + 1) % 2000 == 0:
            print(f"  {file_idx + 1}/{NUM_FILES} files...")

    # main.mini imports files/file_00000.mini as m0 (matching file index)
    main_content = f'''import "files/file_00000.mini" as m0;

fn main() i32 {{
    return m0.{func_name(0, 0)}(1, 2);
}}
'''
    (OUTPUT_DIR / "main.mini").write_text(main_content)

    print(f"\nDone! {NUM_FILES + 1} files in {OUTPUT_DIR}/")
    print(f"All files connected via binary tree structure")
    print(f"\nBenchmark commands:")
    print(f"  cd {OUTPUT_DIR}")
    print(f"  ../../zig-out/bin/comp clean")
    print(f"  time ../../zig-out/bin/comp build main.mini -vv")
    print(f"  time ../../zig-out/bin/comp build main.mini -vv  # incremental")


if __name__ == "__main__":
    main()
