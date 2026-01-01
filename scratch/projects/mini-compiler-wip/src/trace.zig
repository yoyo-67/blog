//! eBPF Tracing Infrastructure
//!
//! This module provides trace points that can be attached via eBPF uprobes.
//! The functions are exported with C ABI so bpftrace can find them by symbol name.
//!
//! Usage with bpftrace:
//!   uprobe:./zig-out/bin/comp:trace_cache_hit { @hits++; }
//!
//! The functions are intentionally empty - they serve only as attachment points.
//! eBPF reads the arguments directly from registers when the probe fires.

const std = @import("std");

// ============================================================================
// Cache Tracing
// ============================================================================

/// Fired when a function is found in the cache (cache hit)
/// Args: function name, name length, ZIR hash
export fn trace_cache_hit(name_ptr: [*]const u8, name_len: usize, hash: u64) callconv(.C) void {
    _ = name_ptr;
    _ = name_len;
    _ = hash;
    // Probe point - eBPF attaches here
}

/// Fired when a function is NOT found in cache (cache miss)
/// Args: function name, name length, ZIR hash
export fn trace_cache_miss(name_ptr: [*]const u8, name_len: usize, hash: u64) callconv(.C) void {
    _ = name_ptr;
    _ = name_len;
    _ = hash;
}

// ============================================================================
// Compilation Tracing
// ============================================================================

/// Fired when compilation of a function starts
/// Args: function name, name length
export fn trace_compile_start(name_ptr: [*]const u8, name_len: usize) callconv(.C) void {
    _ = name_ptr;
    _ = name_len;
}

/// Fired when compilation of a function ends
/// Args: function name, name length, generated IR size in bytes
export fn trace_compile_end(name_ptr: [*]const u8, name_len: usize, ir_size: usize) callconv(.C) void {
    _ = name_ptr;
    _ = name_len;
    _ = ir_size;
}

// ============================================================================
// File I/O Tracing
// ============================================================================

/// Fired after a file stat() call
/// Args: file path, path length, duration in nanoseconds
export fn trace_file_stat(path_ptr: [*]const u8, path_len: usize, duration_ns: u64) callconv(.C) void {
    _ = path_ptr;
    _ = path_len;
    _ = duration_ns;
}

/// Fired after a file read() call
/// Args: file path, path length, duration in nanoseconds
export fn trace_file_read(path_ptr: [*]const u8, path_len: usize, duration_ns: u64) callconv(.C) void {
    _ = path_ptr;
    _ = path_len;
    _ = duration_ns;
}

/// Fired after hashing file contents
/// Args: file path, path length, duration in nanoseconds
export fn trace_file_hash(path_ptr: [*]const u8, path_len: usize, duration_ns: u64) callconv(.C) void {
    _ = path_ptr;
    _ = path_len;
    _ = duration_ns;
}

// ============================================================================
// Convenience Wrappers (for Zig callers)
// ============================================================================

/// Trace a cache hit event
pub fn cacheHit(name: []const u8, hash: u64) void {
    trace_cache_hit(name.ptr, name.len, hash);
}

/// Trace a cache miss event
pub fn cacheMiss(name: []const u8, hash: u64) void {
    trace_cache_miss(name.ptr, name.len, hash);
}

/// Trace compilation start
pub fn compileStart(name: []const u8) void {
    trace_compile_start(name.ptr, name.len);
}

/// Trace compilation end
pub fn compileEnd(name: []const u8, ir_size: usize) void {
    trace_compile_end(name.ptr, name.len, ir_size);
}

/// Trace file stat
pub fn fileStat(path: []const u8, duration_ns: u64) void {
    trace_file_stat(path.ptr, path.len, duration_ns);
}

/// Trace file read
pub fn fileRead(path: []const u8, duration_ns: u64) void {
    trace_file_read(path.ptr, path.len, duration_ns);
}

/// Trace file hash
pub fn fileHash(path: []const u8, duration_ns: u64) void {
    trace_file_hash(path.ptr, path.len, duration_ns);
}
