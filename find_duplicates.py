import os
import hashlib
import sys
from collections import defaultdict


def hash_file(path, chunk_size=65536):
    h = hashlib.md5()
    try:
        with open(path, "rb") as f:
            while chunk := f.read(chunk_size):
                h.update(chunk)
        return h.hexdigest()
    except (OSError, PermissionError):
        return None


MEDIA_EXT = {
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif",
    ".heic", ".webp", ".raw", ".cr2", ".nef", ".arw",
    ".mp4", ".mov", ".avi", ".mkv", ".wmv", ".flv",
    ".m4v", ".3gp", ".mts", ".m2ts", ".mpg", ".mpeg",
}


def find_duplicates(root_dirs, media_only=False):
    size_map = defaultdict(list)
    file_count = 0

    for root in root_dirs:
        print(f"Scanning: {root}")
        for dirpath, _, filenames in os.walk(root):
            print(f"  [{file_count} files] {dirpath[:100]}", end="\r", flush=True)
            for filename in filenames:
                if media_only and os.path.splitext(filename)[1].lower() not in MEDIA_EXT:
                    continue
                filepath = os.path.join(dirpath, filename)
                try:
                    size = os.path.getsize(filepath)
                    if size > 0:
                        size_map[size].append(filepath)
                        file_count += 1
                except (OSError, PermissionError):
                    continue

    print(f"\n\nScan complete: {file_count:,} files found across {len(root_dirs)} location(s).")

    candidates = [(size, paths) for size, paths in size_map.items() if len(paths) > 1]
    total_candidates = sum(len(p) for _, p in candidates)
    print(f"Hashing {total_candidates:,} candidate files (same-size groups)...\n")

    # Store (path, size) so report doesn't need to re-stat files later
    hash_map = defaultdict(list)
    hashed = 0

    for size, paths in candidates:
        for path in paths:
            digest = hash_file(path)
            if digest:
                hash_map[digest].append((path, size))
            hashed += 1
            print(f"  Hashing {hashed}/{total_candidates} files...", end="\r", flush=True)

    print()
    return {h: entries for h, entries in hash_map.items() if len(entries) > 1}


def report(duplicates, output_file=None):
    lines = []

    if not duplicates:
        lines.append("\nNo duplicates found.")
    else:
        total_wasted = 0
        lines.append(f"\nFound {len(duplicates)} duplicate group(s):\n")
        lines.append("=" * 70)

        for i, (digest, entries) in enumerate(duplicates.items(), 1):
            size = entries[0][1]
            wasted = size * (len(entries) - 1)
            total_wasted += wasted
            lines.append(f"Group {i}  [{len(entries)} copies | {size:,} bytes each | {wasted:,} bytes wasted]")
            for path, _ in entries:
                lines.append(f"  {path}")
            lines.append("")

        lines.append("=" * 70)
        lines.append(f"Total wasted space: {total_wasted:,} bytes ({total_wasted / 1_048_576:.1f} MB)")

    output = "\n".join(lines)
    print(output)

    if output_file:
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(output)
        print(f"\nResults saved to: {output_file}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        roots = sys.argv[1:]
    else:
        raw = input("Enter one or more directories to scan (comma-separated): ")
        roots = [r.strip() for r in raw.split(",")]

    output_file = None
    media_only = False

    if "--out" in roots:
        idx = roots.index("--out")
        output_file = roots[idx + 1]
        roots = roots[:idx]

    if "--media-only" in roots:
        media_only = True
        roots = [r for r in roots if r != "--media-only"]

    roots = [os.path.expanduser(r) for r in roots]

    invalid = [r for r in roots if not os.path.isdir(r)]
    if invalid:
        for r in invalid:
            print(f"Not a valid directory: {r}")
        sys.exit(1)

    if media_only:
        print("Mode: photos & videos only")
    dupes = find_duplicates(roots, media_only=media_only)
    report(dupes, output_file)
