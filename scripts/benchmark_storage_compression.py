#!/usr/bin/env python3
"""
Storage Compression and Entropy Benchmark for Sentinel Node Wallet (BTCB2).
Evaluates compression ratios, throughput, and read latencies across offline
quiesced Bitcoin Knots LevelDB UTXO SSTables and raw block files.
"""

import os
import sys
import time
import math
import hashlib
import ctypes
import ctypes.util
import argparse
import subprocess
import tempfile
import shutil
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
    assert decomp_buf.raw[:decomp_size] == data, f"Decompressed data byte mismatch for {name}"

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


def benchmark_buffer_decompression_microbenchmark(data: bytes, chunk_size: int = 4096, iterations: int = 1000):
    """
    Microbenchmark measuring memory buffer lookup vs decompression overhead:
    1. Direct uncompressed random slice (baseline memory lookup)
    2. Compressed chunk decompression on demand (simulated decompress-on-read buffer overhead)
    NOTE: This is a buffer decompression microbenchmark, NOT production RPC P95 latency.
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
        "microbenchmark_penalty_factor": round(decomp_latency_us / direct_latency_us, 1) if direct_latency_us > 0 else 0.0
    }


def generate_quiesced_regtest_snapshot(bin_dir: str):
    """Generates a verified, 100% quiesced and offline regtest dataset."""
    tmp = tempfile.mkdtemp(prefix="knots_quiesced_regtest_")
    bitcoind = os.path.join(bin_dir, "bitcoind")
    bcli = os.path.join(bin_dir, "bitcoin-cli")
    port = 29560 + (os.getpid() % 1000)
    rpcport = port + 1

    conf_path = os.path.join(tmp, "bitcoin.conf")
    with open(conf_path, "w") as f:
        f.write(f"""regtest=1
server=1
listen=0
fallbackfee=0.0001
[regtest]
port={port}
rpcport={rpcport}
rpcuser=test_bench
rpcpassword=test_pass_secure_123
""")

    print(f"Spawning isolated ephemeral bitcoind (port: {port}, rpc: {rpcport})...")
    p = subprocess.Popen([bitcoind, f"-datadir={tmp}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cli_cmd = [bcli, f"-datadir={tmp}", f"-rpcport={rpcport}", "-rpcuser=test_bench", "-rpcpassword=test_pass_secure_123", "-regtest"]

    # Wait for RPC
    ready = False
    for _ in range(20):
        time.sleep(0.5)
        res = subprocess.run(cli_cmd + ["getblockchaininfo"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode == 0:
            ready = True
            break

    if not ready:
        p.kill()
        shutil.rmtree(tmp)
        raise RuntimeError("Failed to start isolated bitcoind regtest instance")

    # Generate 150 blocks to populate blocks/ and chainstate/
    subprocess.run(cli_cmd + ["createwallet", "benchwallet"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    addr = subprocess.check_output(cli_cmd + ["getnewaddress"]).decode().strip()
    subprocess.run(cli_cmd + ["generatetoaddress", "150", addr], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Clean stop to flush all memtables to disk and cleanly shut down LevelDB
    print("Initiating clean stop to flush LevelDB memtables to disk...")
    subprocess.run(cli_cmd + ["stop"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    p.wait(timeout=15)
    print("Daemon stopped cleanly. Snapshot is 100% quiesced and offline.")

    regtest_dir = os.path.join(tmp, "regtest")
    return tmp, os.path.join(regtest_dir, "chainstate"), os.path.join(regtest_dir, "blocks")


def main():
    parser = argparse.ArgumentParser(description="Sentinel Node Wallet Storage Compression Benchmark")
    parser.add_argument("--regtest", action="store_true", default=False, help="Run on isolated quiesced regtest snapshot")
    parser.add_argument("--chainstate-dir", default=None, help="Path to offline quiesced chainstate directory")
    parser.add_argument("--blocks-dir", default=None, help="Path to offline quiesced blocks directory")
    parser.add_argument("--bin-dir", default=os.path.expanduser("~/Developer/NodePocketBTCB2/.cache/bitcoin-29.4.3.knots20260508/bin"))
    parser.add_argument("--max-sample-mb", type=int, default=64, help="Maximum bytes per file sample in MB")
    args = parser.parse_args()

    print("=== Sentinel Node Wallet Storage & Compression Benchmark ===")
    cleanup_dir = None
    if args.chainstate_dir and not args.regtest:
        chainstate_dir = os.path.expanduser(args.chainstate_dir)
        blocks_dir = os.path.expanduser(args.blocks_dir) if args.blocks_dir else None
        mode_label = "OFFLINE SPECIFIED DATASET (Explicit Point-in-time)"
    else:
        print("[ISOLATION MODE] Generating verified offline quiesced regtest dataset...")
        cleanup_dir, chainstate_dir, blocks_dir = generate_quiesced_regtest_snapshot(args.bin_dir)
        mode_label = "OFFLINE QUIESCED REGTEST SNAPSHOT (Deterministic)"

    print(f"Benchmark Mode: {mode_label}")
    print(f"Chainstate Dir: {chainstate_dir}")
    print(f"Blocks Dir:     {blocks_dir}")

    try:
        # Gather full inventory stats
        chainstate_files = []
        total_chainstate_bytes = 0
        if os.path.exists(chainstate_dir):
            for f in os.listdir(chainstate_dir):
                p = os.path.join(chainstate_dir, f)
                if os.path.isfile(p):
                    sz = os.path.getsize(p)
                    total_chainstate_bytes += sz
                    if f.endswith(".ldb") or f.endswith(".log"):
                        chainstate_files.append((f, sz, p))

        blocks_files = []
        total_blocks_bytes = 0
        if os.path.exists(blocks_dir):
            for f in os.listdir(blocks_dir):
                p = os.path.join(blocks_dir, f)
                if os.path.isfile(p):
                    sz = os.path.getsize(p)
                    total_blocks_bytes += sz
                    if f.startswith("blk") or f.startswith("rev"):
                        blocks_files.append((f, sz, p))

        print(f"\nInventory Totals:")
        print(f"  Chainstate Files: {len(chainstate_files)} files ({total_chainstate_bytes / 1024:.2f} KB total)")
        print(f"  Blocks Files:     {len(blocks_files)} files ({total_blocks_bytes / (1024**2):.2f} MB total)")

        samples = []
        for f, sz, p in chainstate_files:
            if sz > 0:
                samples.append((f"chainstate_{f}", (f, sz, p)))
        for f, sz, p in blocks_files:
            if sz > 0:
                samples.append((f"block_{f}", (f, sz, p)))

        max_bytes = args.max_sample_mb * 1024 * 1024
        codecs = [
            ("Apple LZ4", COMPRESSION_LZ4),
            ("Apple LZFSE", COMPRESSION_LZFSE),
            ("Deflate/ZLIB", COMPRESSION_ZLIB),
            ("LZMA", COMPRESSION_LZMA)
        ]

        print("\n--- Running Multi-Sample Empirical Benchmark ---")
        for label, (fname, fsize, fpath) in samples:
            print(f"\nEvaluating {label} [{fname}] (Size: {fsize} bytes)...")
            with open(fpath, "rb") as f:
                raw_data = f.read(max_bytes)

            sha = hashlib.sha256(raw_data).hexdigest()
            entropy = compute_shannon_entropy(raw_data)
            uniformity = (entropy / 8.0) * 100.0

            print(f"  SHA-256: {sha}")
            print(f"  Shannon Entropy: {entropy:.4f} / 8.0000 bits/byte ({uniformity:.2f}% uniform)")

            for cname, ccode in codecs:
                res = benchmark_codec(cname, ccode, raw_data)
                print(f"    {cname:<14} -> {res['compressed_bytes']:6d} B ({res['reduction_pct']:5.2f}% reduction) | "
                      f"Comp: {res['comp_mb_s']:6.1f} MB/s | Decomp: {res['decomp_mb_s']:6.1f} MB/s")

            latency_res = benchmark_buffer_decompression_microbenchmark(raw_data)
            if latency_res:
                print(f"    Decompression Microbenchmark: Direct {latency_res['direct_lookup_latency_us']} µs vs "
                      f"Decompress {latency_res['decompress_on_read_latency_us']} µs "
                      f"({latency_res['microbenchmark_penalty_factor']}x penalty)")

        print("\n=== Benchmark Verification Complete ===")
    finally:
        if cleanup_dir and os.path.exists(cleanup_dir):
            shutil.rmtree(cleanup_dir)
            print(f"Cleaned up isolated test environment: {cleanup_dir}")


if __name__ == "__main__":
    main()
