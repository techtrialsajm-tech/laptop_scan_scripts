# File Mover & Duplicate Finder

Utilities for organizing, moving, and deduplicating files across drives and folders.

---

## find_duplicates.py

Scans one or more directories recursively to find exact duplicate files using MD5 hashing.

**How it works:**
1. Walks all directories and groups files by size (fast pre-filter)
2. MD5-hashes only files that share the same size
3. Reports confirmed byte-for-byte duplicates grouped together

**Usage:**
```bash
# Single drive or folder
python find_duplicates.py "D:\"

# Multiple folders (finds duplicates within and across all of them)
python find_duplicates.py "E:\Photos" "F:\Backup"

# Photos and videos only
python find_duplicates.py "E:\Photos" "F:\" --media-only

# Save results to file
python find_duplicates.py "E:\Photos" --out results.txt

# Combine flags
python find_duplicates.py "E:\Photos" "F:\" --media-only --out results_EF.txt
```

**Supported media extensions** (used with `--media-only`):
- Images: `.jpg .jpeg .png .gif .bmp .tiff .heic .webp .raw .cr2 .nef .arw`
- Videos: `.mp4 .mov .avi .mkv .wmv .flv .m4v .3gp .mts .m2ts .mpg .mpeg`

**Sample output:**
```
Scanning: E:\Photos
  [21,996 files] E:\Photos\Tony\USA\NYC

Scan complete: 21,996 files found across 2 location(s).
Hashing 6,379 candidate files (same-size groups)...

Found 42 duplicate group(s):

======================================================================
Group 1  [2 copies | 4,089,780 bytes each | 4,089,780 bytes wasted]
  E:\Photos\wedding\DSC03886.JPG
  E:\Backup\DSC03886.JPG

======================================================================
Total wasted space: 523,481,234 bytes (499.2 MB)
```

---

## mover.py

Moves files between folders based on configurable rules.

---

## check_usb.ps1

PowerShell utility to check USB drive connectivity and status.
