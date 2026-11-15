#!/usr/bin/env python3
"""
Storage Compression and Entropy Benchmark for Sentinel Node Wallet (BTCB2).
Empirically evaluates compression ratios, throughput, and read latencies across
active Bitcoin Knots LevelDB UTXO SSTables and raw block files.
"""

import os
import sys
import time
import math
import hashlib
import ctypes
import ctypes.util
import argparse
from collections import Counter

# Load Apple libcompression for native hardware/SIMD acceleration
LIB_NAME = ctypes.util.find_library("compression")
if not LIB_NAME:
    raise RuntimeError("Apple libcompression library not found")
libcomp = ctypes.CDLL(LIB_NAME)

libcomp.compression_encode_buffer.restype = ctypes.c_size_t
libcomp.compression_encode_buffer.argtypes = [
    ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_void_p, ctypes.c_int
]

libcomp.compression_decode_buffer.restype = ctypes.c_size_t
libcomp.compression_decode_buffer.argtypes = [
    ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_void_p, ctypes.c_int
]

# Apple Compression algorithm constants
COMPRESSION_LZ4 = 0x100
COMPRESSION_ZLIB = 0x205
COMPRESSION_LZMA = 0x306
COMPRESSION_LZFSE = 0x801


def compute_shannon_entropy(data: bytes) -> float:
    """Computes Shannon entropy in bits per byte (max 8.0000)."""
    if not data:
        return 0.0
    counts = Counter(data)
    total = len(data)
    return -sum((c / total) * math.log2(c / total) for c in counts.values())


def benchmark_codec(name: str, algo_code: int, data: bytes):
    """Benchmarks compression and decompression of a buffer using libcompression."""
    src_len = len(data)
    dst_buf = ctypes.create_string_buffer(max(src_len * 2, 65536))

    # Compression
    t0 = time.perf_counter()
    comp_size = libcomp.compression_encode_buffer(
        dst_buf, len(dst_buf),
        data, src_len,
        None, algo_code
    )
    t_comp = time.perf_counter() - t0

    if comp_size == 0:
        return {
            "name": name,
            "compressed_bytes": src_len,
            "reduction_pct": 0.0,
            "comp_mb_s": 0.0,
            "decomp_mb_s": 0.0,
            "error": "compression_failed_or_expanded"
        }

    # Decompression
    comp_bytes = dst_buf.raw[:comp_size]
    decomp_buf = ctypes.create_string_buffer(src_len)
    t1 = time.perf_counter()
    decomp_size = libcomp.compression_decode_buffer(
        decomp_buf, src_len,
        comp_bytes, comp_size,
        None, algo_code
    )
    t_decomp = time.perf_counter() - t1

    assert decomp_size == src_len, f"Decompressed size mismatch for {name}"

    reduction_pct = ((src_len - comp_size) / src_len) * 100.0
    comp_mb_s = (src_len / (1024 * 1024)) / t_comp if t_comp > 0 else 0.0
    decomp_mb_s = (src_len / (1024 * 1024)) / t_decomp if t_decomp > 0 else 0.0

    return {
        "name": name,
        "compressed_bytes": comp_size,
        "reduction_pct": round(reduction_pct, 2),
        "comp_time_ms": round(t_comp * 1000, 2),
        "comp_mb_s": round(comp_mb_s, 2),
        "decomp_time_ms": round(t_decomp * 1000, 2),
        "decomp_mb_s": round(decomp_mb_s, 2)
    }


def benchmark_random_point_reads(data: bytes, chunk_size: int = 4096, iterations: int = 1000):
    """
    Simulates random point lookups:
    1. Direct uncompressed random slice (baseline mmap lookup)
    2. Compressed chunk decompression on demand (simulated compressed LevelDB block lookup)
    """
    import random
    if len(data) < chunk_size * 2:
        return None

    max_offset = len(data) - chunk_size
    offsets = [random.randint(0, max_offset) for _ in range(iterations)]

    # 1. Direct uncompressed slice (memory lookup)
    t0 = time.perf_counter()
    for off in offsets:
        _ = data[off:off + chunk_size]
    t_direct = time.perf_counter() - t0
    direct_latency_us = (t_direct / iterations) * 1_000_000

    # 2. Decompress 4KB chunk on demand using LZ4
    # Pre-compress 4KB blocks
    compressed_chunks = []
    dst_buf = ctypes.create_string_buffer(chunk_size * 2)
    for off in offsets[:100]:  # sample 100 chunks
        chunk = data[off:off + chunk_size]
        csz = libcomp.compression_encode_buffer(dst_buf, len(dst_buf), chunk, len(chunk), None, COMPRESSION_LZ4)
        if csz > 0:
            compressed_chunks.append(dst_buf.raw[:csz])

    decomp_buf = ctypes.create_string_buffer(chunk_size)
    t1 = time.perf_counter()
    decomp_count = 0
    for cchunk in compressed_chunks:
        _ = libcomp.compression_decode_buffer(decomp_buf, chunk_size, cchunk, len(cchunk), None, COMPRESSION_LZ4)
        decomp_count += 1
    t_decomp = time.perf_counter() - t1
    decomp_latency_us = (t_decomp / decomp_count) * 1_000_000 if decomp_count > 0 else 0.0

    return {
        "direct_lookup_latency_us": round(direct_latency_us, 3),
        "decompress_on_read_latency_us": round(decomp_latency_us, 3),
        "latency_penalty_factor": round(decomp_latency_us / direct_latency_us, 1) if direct_latency_us > 0 else 0.0
    }


def main():
    parser = argparse.ArgumentParser(description="Sentinel Node Wallet Storage Compression Benchmark")
    parser.add_argument("--chainstate-dir", default=os.path.expanduser("~/Library/Application Support/NodePocketBTCB2/chainstate"))
    parser.add_argument("--blocks-dir", default=os.path.expanduser("~/Library/Application Support/NodePocketBTCB2/blocks"))
    parser.add_argument("--max-sample-mb", type=int, default=64, help="Maximum bytes per file sample in MB")
    args = parser.parse_args()

    print("=== Sentinel Node Wallet Storage & Compression Benchmark ===")
    print(f"Chainstate Dir: {args.chainstate_dir}")
    print(f"Blocks Dir:     {args.blocks_dir}")

    # Gather full inventory stats
    chainstate_files = []
    total_chainstate_bytes = 0
    if os.path.exists(args.chainstate_dir):
        for f in os.listdir(args.chainstate_dir):
            p = os.path.join(args.chainstate_dir, f)
            if os.path.isfile(p):
                sz = os.path.getsize(p)
                total_chainstate_bytes += sz
                if f.endswith(".ldb"):
                    chainstate_files.append((f, sz, p))

    blocks_files = []
    total_blocks_bytes = 0
    if os.path.exists(args.blocks_dir):
        for f in os.listdir(args.blocks_dir):
            p = os.path.join(args.blocks_dir, f)
            if os.path.isfile(p):
                sz = os.path.getsize(p)
                total_blocks_bytes += sz
                if f.startswith("blk") or f.startswith("rev"):
                    blocks_files.append((f, sz, p))

    print(f"\nInventory Totals:")
    print(f"  Chainstate Files: {len(chainstate_files)} .ldb tables ({total_chainstate_bytes / (1024**3):.2f} GB total)")
    print(f"  Blocks Files:     {len(blocks_files)} files ({total_blocks_bytes / (1024**2):.2f} MB total)")

    # Select representative samples
    samples = []
    if chainstate_files:
        sorted_ldb = sorted(chainstate_files, key=lambda x: x[1])
        # Smallest
        samples.append(("small_sstable", sorted_ldb[0]))
        # Medium
        med_idx = len(sorted_ldb) // 2
        samples.append(("medium_sstable", sorted_ldb[med_idx]))
        # Largest 2
        samples.append(("large_sstable_1", sorted_ldb[-1]))
        if len(sorted_ldb) > 1:
            samples.append(("large_sstable_2", sorted_ldb[-2]))

    if blocks_files:
        # One raw block file and one rev file
        blk = next((b for b in blocks_files if b[0].startswith("blk")), None)
        if blk:
            samples.append(("raw_block_file", blk))
        rev = next((b for b in blocks_files if b[0].startswith("rev")), None)
        if rev:
            samples.append(("undo_reorg_file", rev))

    max_bytes = args.max_sample_mb * 1024 * 1024
    results = []

    print("\n--- Running Multi-Sample Empirical Benchmark ---")
    codecs = [
        ("Apple LZ4", COMPRESSION_LZ4),
        ("Apple LZFSE", COMPRESSION_LZFSE),
        ("Deflate/ZLIB", COMPRESSION_ZLIB),
        ("LZMA", COMPRESSION_LZMA)
    ]

    for label, (fname, fsize, fpath) in samples:
        print(f"\nEvaluating {label} [{fname}] (Original: {fsize / (1024*1024):.2f} MB)...")
        with open(fpath, "rb") as f:
            raw_data = f.read(max_bytes)

        sha = hashlib.sha256(raw_data).hexdigest()
        entropy = compute_shannon_entropy(raw_data)
        uniformity = (entropy / 8.0) * 100.0

        print(f"  SHA-256: {sha[:16]}... ({len(raw_data)} bytes sampled)")
        print(f"  Shannon Entropy: {entropy:.4f} / 8.0000 bits/byte ({uniformity:.2f}% uniform)")

        codec_results = []
        for cname, ccode in codecs:
            res = benchmark_codec(cname, ccode, raw_data)
            codec_results.append(res)
            print(f"    {cname:<14} -> {res['compressed_bytes'] / (1024*1024):6.2f} MB ({res['reduction_pct']:5.2f}% reduction) | "
                  f"Comp: {res['comp_mb_s']:6.1f} MB/s | Decomp: {res['decomp_mb_s']:6.1f} MB/s")

        latency_results = benchmark_random_point_reads(raw_data)
        if latency_results:
            print(f"    Random Point Read Latency: Direct {latency_results['direct_lookup_latency_us']} µs vs "
                  f"Decompress {latency_results['decompress_on_read_latency_us']} µs "
                  f"({latency_results['latency_penalty_factor']}x penalty)")

        results.append({
            "category": label,
            "filename": fname,
            "sample_bytes": len(raw_data),
            "file_bytes": fsize,
            "sha256": sha,
            "entropy": round(entropy, 4),
            "uniformity_pct": round(uniformity, 2),
            "codecs": codec_results,
            "latency": latency_results
        })

    # Summary of Findings
    print("\n=== Benchmark Summary ===")
    print("Across all sampled LevelDB SSTables:")
    avg_entropy = sum(r["entropy"] for r in results if "sstable" in r["category"]) / max(1, len([r for r in results if "sstable" in r["category"]]))
    print(f"  Average Shannon Entropy: {avg_entropy:.4f} bits/byte")
    best_reduction = max(max(c["reduction_pct"] for c in r["codecs"]) for r in results if "sstable" in r["category"])
    print(f"  Maximum Achievable Compression: {best_reduction:.2f}%")
    print(f"  Estimated Incompressible Portion: {100.0 - best_reduction:.2f}% of UTXO database")

    return results


if __name__ == "__main__":
    main()
