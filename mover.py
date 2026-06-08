"""
File Mover - High-throughput batch file transfer from source to target.
Usage: python mover.py [source] [target]
       (prompts if args not provided)
"""

import os
import sys
import shutil
import hashlib
import time
import tempfile
import threading
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import List, Tuple
import argparse

# ── Fixed constants (auto-tuned values override at runtime) ───────────────────
LARGE_FILE_THRESHOLD = 100 * 1024 * 1024   # 100 MB  → chunked copy path
VERIFY_CHECKSUMS     = True                 # SHA-256 verify after copy
LOW_SPACE_MARGIN     = 500 * 1024 * 1024   # abort if target has < 500 MB free
BENCH_SIZE           = 64 * 1024 * 1024    # 64 MB benchmark payload
# ─────────────────────────────────────────────────────────────────────────────


@dataclass
class FileTask:
    src: Path
    dst: Path
    size: int


@dataclass
class Stats:
    total_files: int = 0
    total_bytes: int = 0
    copied_files: int = 0
    copied_bytes: int = 0
    failed: List[str] = field(default_factory=list)
    skipped: int = 0
    lock: threading.Lock = field(default_factory=threading.Lock)


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


# ── Drive benchmarking ────────────────────────────────────────────────────────

def _bench_read(path: Path, chunk: int) -> float:
    """Sequential read speed in bytes/s over BENCH_SIZE data."""
    # Find the first readable file >= BENCH_SIZE, else read what we can
    target_file = None
    for root, _, files in os.walk(path):
        for f in files:
            fp = Path(root) / f
            try:
                if fp.stat().st_size >= BENCH_SIZE:
                    target_file = fp
                    break
            except OSError:
                continue
        if target_file:
            break

    if not target_file:
        # Fall back: read as many files as needed to hit BENCH_SIZE
        target_file = None
        for root, _, files in os.walk(path):
            for f in files:
                fp = Path(root) / f
                try:
                    if fp.stat().st_size > 0:
                        target_file = fp
                        break
                except OSError:
                    continue
            if target_file:
                break

    if not target_file:
        return 0.0

    read = 0
    start = time.perf_counter()
    with open(target_file, "rb") as fh:
        while read < BENCH_SIZE:
            data = fh.read(chunk)
            if not data:
                break
            read += len(data)
    elapsed = time.perf_counter() - start
    return read / elapsed if elapsed > 0 else 0.0


def _bench_write(path: Path, chunk: int) -> float:
    """Sequential write speed in bytes/s using a temp file."""
    tmp = path / ".mover_bench_tmp"
    data = b"\x00" * chunk
    written = 0
    try:
        start = time.perf_counter()
        with open(tmp, "wb") as fh:
            while written < BENCH_SIZE:
                fh.write(data)
                written += len(data)
            fh.flush()
            os.fsync(fh.fileno())
        elapsed = time.perf_counter() - start
        return written / elapsed if elapsed > 0 else 0.0
    except OSError:
        return 0.0
    finally:
        tmp.unlink(missing_ok=True)


def benchmark_drives(source: Path, target: Path) -> Tuple[float, float, int, int, int]:
    """
    Measure read speed on source and write speed on target.
    Returns (read_bps, write_bps, chunk_size, small_workers, large_workers).
    """
    print("Benchmarking drives…", end=" ", flush=True)

    # Start with a conservative chunk for the benchmark itself
    probe_chunk = 4 * 1024 * 1024  # 4 MB

    read_bps  = _bench_read(source, probe_chunk)
    write_bps = _bench_write(target, probe_chunk)

    # Bottleneck is the slower of the two
    bottleneck = min(read_bps, write_bps) if read_bps and write_bps else (read_bps or write_bps)

    # ── Derive chunk size ──────────────────────────────────────────────────
    # Larger chunks reduce syscall overhead on fast drives;
    # smaller chunks keep memory pressure low on slow drives.
    if bottleneck >= 300 * 1024 * 1024:       # ≥ 300 MB/s  (USB 3.1 SSD)
        chunk_size    = 32 * 1024 * 1024
        small_workers = 8
        large_workers = 4
    elif bottleneck >= 100 * 1024 * 1024:     # ≥ 100 MB/s  (USB 3.0 HDD / fast card)
        chunk_size    = 16 * 1024 * 1024
        small_workers = 6
        large_workers = 3
    elif bottleneck >= 30 * 1024 * 1024:      # ≥  30 MB/s  (USB 2.0 fast / SD UHS-I)
        chunk_size    = 8 * 1024 * 1024
        small_workers = 4
        large_workers = 2
    else:                                      # <  30 MB/s  (slow card / USB 2.0 HDD)
        chunk_size    = 4 * 1024 * 1024
        small_workers = 2
        large_workers = 1

    r_str = f"{human(read_bps)}/s" if read_bps else "n/a"
    w_str = f"{human(write_bps)}/s" if write_bps else "n/a"
    print(f"read {r_str}  write {w_str}")
    print(
        f"Auto-tuned → chunk {human(chunk_size)}  "
        f"workers small={small_workers} large={large_workers}"
    )
    return read_bps, write_bps, chunk_size, small_workers, large_workers


# ── Core copy logic ───────────────────────────────────────────────────────────

def sha256(path: Path, chunk_size: int) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while data := f.read(chunk_size):
            h.update(data)
    return h.hexdigest()


def copy_file(task: FileTask, stats: Stats, chunk_size: int) -> bool:
    """Copy one file, preserving metadata. Returns True on success."""
    try:
        task.dst.parent.mkdir(parents=True, exist_ok=True)

        if task.size >= LARGE_FILE_THRESHOLD:
            with open(task.src, "rb") as src_f, open(task.dst, "wb") as dst_f:
                while chunk := src_f.read(chunk_size):
                    free = shutil.disk_usage(task.dst.parent).free
                    if free < LOW_SPACE_MARGIN:
                        raise OSError(f"Target drive low on space: only {human(free)} remaining")
                    dst_f.write(chunk)
                    with stats.lock:
                        stats.copied_bytes += len(chunk)
        else:
            shutil.copy2(task.src, task.dst)
            with stats.lock:
                stats.copied_bytes += task.size

        shutil.copystat(task.src, task.dst)

        if VERIFY_CHECKSUMS:
            if sha256(task.src, chunk_size) != sha256(task.dst, chunk_size):
                raise ValueError("Checksum mismatch after copy")

        with stats.lock:
            stats.copied_files += 1
        return True

    except Exception as e:
        with stats.lock:
            stats.failed.append(f"{task.src}  →  {e}")
        if task.dst.exists():
            task.dst.unlink(missing_ok=True)
        return False


def collect_tasks(source: Path, target: Path, stats: Stats) -> List[FileTask]:
    tasks: List[FileTask] = []
    for root, dirs, files in os.walk(source):
        dirs.sort()
        rel_root = Path(root).relative_to(source)
        for name in sorted(files):
            src = Path(root) / name
            dst = target / rel_root / name
            try:
                size = src.stat().st_size
            except OSError:
                stats.failed.append(f"{src}  →  cannot stat")
                continue

            if dst.exists():
                try:
                    ds, ss = dst.stat(), src.stat()
                    if ds.st_size == ss.st_size and abs(ds.st_mtime - ss.st_mtime) < 2:
                        with stats.lock:
                            stats.skipped += 1
                        continue
                except OSError:
                    pass

            tasks.append(FileTask(src=src, dst=dst, size=size))
            stats.total_files += 1
            stats.total_bytes += size

    return tasks


def progress_printer(stats: Stats, stop_event: threading.Event):
    start = time.time()
    while not stop_event.is_set():
        time.sleep(1)
        elapsed = time.time() - start
        with stats.lock:
            done  = stats.copied_bytes
            files = stats.copied_files
            total = stats.total_bytes
            tf    = stats.total_files
        pct     = (done / total * 100) if total else 0
        speed   = done / elapsed if elapsed else 0
        eta     = ((total - done) / speed) if speed and total > done else 0
        bar_w   = 30
        filled  = int(bar_w * pct / 100)
        bar     = "█" * filled + "░" * (bar_w - filled)
        eta_str = f"{int(eta//60)}m{int(eta%60):02d}s" if eta else "--"
        print(
            f"\r[{bar}] {pct:5.1f}%  "
            f"{files}/{tf} files  "
            f"{human(done)}/{human(total)}  "
            f"{human(speed)}/s  ETA {eta_str}   ",
            end="", flush=True,
        )
    print()


# ── Main run ──────────────────────────────────────────────────────────────────

def run(source: Path, target: Path, force_workers: int = None):
    print(f"\nSource : {source}")
    print(f"Target : {target}")
    print(f"Verify : {'SHA-256' if VERIFY_CHECKSUMS else 'off'}\n")

    if not source.exists():
        sys.exit(f"ERROR: source path does not exist: {source}")
    target.mkdir(parents=True, exist_ok=True)

    # ── Benchmark & auto-tune ─────────────────────────────────────────────
    _, _, chunk_size, small_workers, large_workers = benchmark_drives(source, target)

    if force_workers:
        small_workers = force_workers
        large_workers = max(1, force_workers // 2)
        print(f"Worker override → small={small_workers} large={large_workers}")

    print()

    # ── Scan ──────────────────────────────────────────────────────────────
    stats = Stats()
    print("Scanning source…")
    tasks = collect_tasks(source, target, stats)

    if not tasks:
        print(f"Nothing to copy. ({stats.skipped} file(s) already up-to-date)")
        return

    print(f"Found {stats.total_files} file(s) totalling {human(stats.total_bytes)}")
    if stats.skipped:
        print(f"Skipping {stats.skipped} already-copied file(s)")

    # ── Space check ───────────────────────────────────────────────────────
    target_free = shutil.disk_usage(target).free
    print(f"Target free : {human(target_free)}  |  Need : {human(stats.total_bytes)}")
    if target_free < stats.total_bytes + LOW_SPACE_MARGIN:
        shortfall = stats.total_bytes + LOW_SPACE_MARGIN - target_free
        sys.exit(
            f"\nERROR: Not enough space on target.\n"
            f"  Available : {human(target_free)}\n"
            f"  Required  : {human(stats.total_bytes)} + {human(LOW_SPACE_MARGIN)} buffer\n"
            f"  Shortfall : {human(shortfall)}\n"
            "Free up space on the target drive and try again."
        )
    print()

    # ── Copy ──────────────────────────────────────────────────────────────
    small = [t for t in tasks if t.size < LARGE_FILE_THRESHOLD]
    large = [t for t in tasks if t.size >= LARGE_FILE_THRESHOLD]

    stop_event = threading.Event()
    printer = threading.Thread(target=progress_printer, args=(stats, stop_event), daemon=True)
    printer.start()

    start = time.time()

    with ThreadPoolExecutor(max_workers=large_workers) as ex:
        for _ in as_completed({ex.submit(copy_file, t, stats, chunk_size): t for t in large}):
            pass

    with ThreadPoolExecutor(max_workers=small_workers) as ex:
        for _ in as_completed({ex.submit(copy_file, t, stats, chunk_size): t for t in small}):
            pass

    stop_event.set()
    printer.join()

    elapsed   = time.time() - start
    avg_speed = stats.total_bytes / elapsed if elapsed else 0

    print(f"\n{'─'*60}")
    print(f"Completed in {elapsed:.1f}s  |  avg {human(avg_speed)}/s")
    print(f"Copied  : {stats.copied_files} file(s)  ({human(stats.copied_bytes)})")
    if stats.skipped:
        print(f"Skipped : {stats.skipped} (already up-to-date)")
    if stats.failed:
        print(f"\nFAILED  : {len(stats.failed)} file(s)")
        for msg in stats.failed:
            print(f"  ✗  {msg}")
    else:
        print("Errors  : none")
    print(f"{'─'*60}\n")


def main():
    parser = argparse.ArgumentParser(description="High-throughput file mover")
    parser.add_argument("source", nargs="?", help="Source directory or drive root")
    parser.add_argument("target", nargs="?", help="Target directory or drive root")
    parser.add_argument("--no-verify", action="store_true", help="Skip checksum verification")
    parser.add_argument("--workers", type=int, default=None, help="Override worker count")
    args = parser.parse_args()

    global VERIFY_CHECKSUMS
    if args.no_verify:
        VERIFY_CHECKSUMS = False

    source_str = args.source or input("Source path (e.g. E:\\  or  D:\\Photos): ").strip().strip('"')
    target_str = args.target or input("Target path (e.g. F:\\Backup):            ").strip().strip('"')

    run(Path(source_str), Path(target_str), force_workers=args.workers)


if __name__ == "__main__":
    main()
