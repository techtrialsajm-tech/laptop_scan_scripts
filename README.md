# Laptop Scan Scripts

A collection of PowerShell scripts and Python utilities for Windows storage cleanup, security repair, performance optimisation, and high-throughput file transfer.

> Run PowerShell scripts as **Administrator** for full functionality.
> Execute with: `powershell -ExecutionPolicy Bypass -File .\<script-name>.ps1`

---

## File Transfer

### `mover.py` — High-Throughput File Mover

Batch-copies files from one drive to another (e.g. source USB/memory card → target hard drive), maximising transfer speed automatically.

**Features:**
- Benchmarks read speed on source and write speed on target before copying
- Auto-tunes chunk size and parallel worker count based on measured speeds
- Copies large files (≥ 100 MB) with chunked streaming — never buffers to the internal drive
- Skips files already present at the destination (safe to re-run)
- SHA-256 checksum verification after every file
- Pre-flight check: aborts if target doesn't have enough free space
- Mid-transfer space check: stops cleanly if the drive fills up
- Live progress bar with speed and ETA

**Requirements:** Python 3.8+

```powershell
# Interactive — prompts for source and target
python mover.py

# Direct paths
python mover.py E:\ F:\Backup

# Skip checksum verification (faster)
python mover.py E:\ F:\Backup --no-verify

# Override worker count
python mover.py E:\ F:\Backup --workers 4
```

---

### `check_usb.ps1` — USB Drive Inspector

Lists all connected drives with size, free space, and drive letters. Detects USB host controller generation (2.0 / 3.0 / 3.1) and shows theoretical max speed.

```powershell
powershell -ExecutionPolicy Bypass -File .\check_usb.ps1
```

---

## Scripts

| Script | Purpose | Run As Admin | Modifies System |
|---|---|---|---|
| `mover.py` | High-throughput file transfer from source to target drive. Auto-benchmarks drives and tunes parallel workers. | No | No — copies only |
| `check_usb.ps1` | Lists connected drives and USB controller speeds. | No | No — read only |
| `find-large-files.ps1` | Scans user profile for large files and folders. Shows top offenders by size with Claude Desktop VM breakdown. | Recommended | No — read only |
| `full-scan.ps1` | Full C:\ storage scan. Lists safe-to-delete cache folders with sizes, top 30 largest files, top 30 largest folders, and all `node_modules` folders. | Recommended | No — read only |
| `claude-breakdown.ps1` | Deep size breakdown of the Claude Desktop package folder (`Claude_pzs8sxrjxfjjc`). Identifies live VM files vs safe-to-delete backups. | No | No — read only |
| `check-antivirus.ps1` | Audits active antivirus status via Windows Security Center, running services, installed programs, and Windows Defender state. Detects conflicts between multiple AV products. | Yes | No — read only |
| `defender-fix.ps1` | Diagnoses and fixes Windows Defender when disabled by a third-party AV (e.g. McAfee). Removes blocking registry policies and re-enables real-time protection. | Yes | Yes — registry + services |
| `check-dell.ps1` | Checks for Dell software remnants after uninstall — scans registry, running processes, services, scheduled tasks, and program folders. | No | No — read only |
| `boost-performance.ps1` | Tunes RAM, disk, CPU, and network for maximum performance. Sets High Performance power plan, disables CPU throttling and core parking, enables SSD TRIM, disables telemetry services, removes visual effects, and lowers network latency. | Yes | Yes — registry + services + power plan |
| `startup-analyser.ps1` | Analyses boot time and startup load. Shows last boot duration, all auto-launch programs (colour-coded safe/keep/review), automatic-start services, boot delay events from Windows event log, and ready-to-run disable commands. | Yes | No — read only |

---

## Quick Reference — What to Delete Safely

| Location | Safe to Delete | Notes |
|---|---|---|
| `C:\Windows\Temp\*` | Yes | Windows temp files |
| `%TEMP%\*` | Yes | User temp files |
| `C:\Windows\SoftwareDistribution\Download\*` | Yes | Downloaded Windows updates already installed |
| `C:\Windows\Prefetch\*` | Yes | App launch cache — rebuilds itself |
| `C:\Windows\Panther\setupact.log` | Yes | Windows upgrade log |
| `C:\Windows\Panther\MigLog.xml` | Yes | Windows migration log |
| `C:\$WinREAgent\Scratch\*` | Yes | Temp files from Windows update |
| Chrome / Edge Cache folders | Yes | Browser cache — no login impact |
| `%LOCALAPPDATA%\pip\Cache\*` | Yes | pip package download cache |
| Claude `rootfs.vhdx.zst` | Yes | Compressed VM backup — 2+ GB, auto-regenerated |
| Claude `initrd.zst` | Yes | Compressed VM boot backup — auto-regenerated |
| `C:\ProgramData\McAfee\*` | Yes (if uninstalled) | McAfee leaves 14+ GB behind after uninstall |

---

## Windows Defender Recovery

If Defender was disabled by McAfee or another AV:

1. Uninstall the third-party AV using its official removal tool
2. Run `defender-fix.ps1` as Administrator
3. Reboot
4. Verify: `Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled`

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or later
- Administrator privileges (for scripts that modify system settings)

---

## License

MIT — see [LICENSE](LICENSE)
