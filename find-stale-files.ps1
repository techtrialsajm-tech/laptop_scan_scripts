# Stale File Finder - files/folders created but never or rarely accessed
# Run as Administrator for full results
# Skips system folders, focuses on user-created content

param(
    [int]$DaysOld = 180,        # Flag files not accessed in this many days
    [long]$MinSizeMB = 1,       # Minimum file size to report (MB)
    [switch]$IncludeSmall       # Include files under MinSizeMB
)

function Format-Size {
    param([long]$bytes)
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    return "{0:N2} KB" -f ($bytes / 1KB)
}

function Get-FolderSize {
    param([string]$path)
    try {
        $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                 Where-Object { -not $_.PSIsContainer } |
                 Measure-Object -Property Length -Sum).Sum
        if ($size) { return [long]$size } else { return 0 }
    } catch { return 0 }
}

$cutoff    = (Get-Date).AddDays(-$DaysOld)
$now       = Get-Date
$minBytes  = $MinSizeMB * 1MB

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STALE FILE FINDER" -ForegroundColor Cyan
Write-Host " Threshold  : not accessed in $DaysOld+ days (before $($cutoff.ToString('yyyy-MM-dd')))" -ForegroundColor Cyan
Write-Host " Min size   : $(Format-Size $minBytes)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ============================================================
# SECTION 1 — NEVER ACCESSED (LastAccessTime = CreationTime)
# Files created and never opened
# ============================================================
Write-Host ""
Write-Host "=== FILES CREATED BUT NEVER ACCESSED ===" -ForegroundColor Yellow
Write-Host "(LastAccessTime within 60s of CreationTime)" -ForegroundColor Gray
Write-Host ""

$scanPaths = @(
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Pictures",
    "$env:USERPROFILE\Videos",
    "$env:USERPROFILE\Music",
    "$env:LOCALAPPDATA\Programs",
    "$env:APPDATA"
)

$neverAccessed = @()
foreach ($path in $scanPaths) {
    if (-not (Test-Path $path)) { continue }
    Get-ChildItem $path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Length -ge $minBytes -and
            $_.CreationTime -lt $cutoff -and
            [math]::Abs(($_.LastAccessTime - $_.CreationTime).TotalSeconds) -lt 60
        } | ForEach-Object {
            $neverAccessed += [PSCustomObject]@{
                Path         = $_.FullName
                Size         = $_.Length
                SizeStr      = Format-Size $_.Length
                Created      = $_.CreationTime.ToString("yyyy-MM-dd")
                LastAccessed = $_.LastAccessTime.ToString("yyyy-MM-dd")
                AgeDays      = [int]($now - $_.CreationTime).TotalDays
            }
        }
}

$neverAccessed | Sort-Object Size -Descending | Select-Object -First 40 | ForEach-Object {
    $color = if ($_.Size -gt 100MB) { "Red" } elseif ($_.Size -gt 10MB) { "Yellow" } else { "White" }
    Write-Host ("{0,-70} {1,10}  created:{2}  age:{3}d" -f $_.Path, $_.SizeStr, $_.Created, $_.AgeDays) -ForegroundColor $color
}
$neverTotal = ($neverAccessed | Measure-Object -Property Size -Sum).Sum
Write-Host ""
Write-Host ("  Total: {0} files — {1}" -f $neverAccessed.Count, (Format-Size ([long]($neverTotal ?? 0)))) -ForegroundColor Cyan

# ============================================================
# SECTION 2 — OLD DOWNLOADS (most common junk accumulator)
# ============================================================
Write-Host ""
Write-Host "=== DOWNLOADS FOLDER — NOT ACCESSED IN $DaysOld+ DAYS ===" -ForegroundColor Yellow
Write-Host ""

$downloads = "$env:USERPROFILE\Downloads"
if (Test-Path $downloads) {
    $oldDownloads = Get-ChildItem $downloads -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastAccessTime -lt $cutoff } |
        ForEach-Object {
            $size = if ($_.PSIsContainer) { Get-FolderSize $_.FullName } else { $_.Length }
            [PSCustomObject]@{
                Name         = $_.Name
                Path         = $_.FullName
                Size         = $size
                SizeStr      = Format-Size $size
                Type         = if ($_.PSIsContainer) { "Folder" } else { $_.Extension }
                LastAccessed = $_.LastAccessTime.ToString("yyyy-MM-dd")
                AgeDays      = [int]($now - $_.LastAccessTime).TotalDays
            }
        } | Where-Object { $_.Size -ge $minBytes }

    $oldDownloads | Sort-Object Size -Descending | ForEach-Object {
        $color = if ($_.Size -gt 100MB) { "Red" } elseif ($_.Size -gt 10MB) { "Yellow" } else { "White" }
        Write-Host ("{0,-45} {1,-10} {2,10}  last:{3}  age:{4}d" -f $_.Name, $_.Type, $_.SizeStr, $_.LastAccessed, $_.AgeDays) -ForegroundColor $color
    }
    $dlTotal = ($oldDownloads | Measure-Object -Property Size -Sum).Sum
    Write-Host ""
    Write-Host ("  Total: {0} items — {1}" -f $oldDownloads.Count, (Format-Size ([long]($dlTotal ?? 0)))) -ForegroundColor Cyan
}

# ============================================================
# SECTION 3 — STALE FOLDERS IN USER PROFILE
# Folders not touched in 180+ days
# ============================================================
Write-Host ""
Write-Host "=== STALE FOLDERS (not modified in $DaysOld+ days) ===" -ForegroundColor Yellow
Write-Host ""

$staleFolderRoots = @(
    "$env:USERPROFILE",
    "$env:APPDATA",
    "$env:LOCALAPPDATA"
)

$staleFolders = @()
foreach ($root in $staleFolderRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -lt $cutoff -and
            $_.Name -notmatch "^(Microsoft|Windows|Temp|Local Settings|Application Data)$"
        } | ForEach-Object {
            $size = Get-FolderSize $_.FullName
            if ($size -ge ($minBytes * 10)) {
                $staleFolders += [PSCustomObject]@{
                    Path         = $_.FullName
                    Size         = $size
                    SizeStr      = Format-Size $size
                    LastModified = $_.LastWriteTime.ToString("yyyy-MM-dd")
                    AgeDays      = [int]($now - $_.LastWriteTime).TotalDays
                }
            }
        }
}

$staleFolders | Sort-Object Size -Descending | Select-Object -First 30 | ForEach-Object {
    $color = if ($_.Size -gt 500MB) { "Red" } elseif ($_.Size -gt 50MB) { "Yellow" } else { "White" }
    Write-Host ("{0,-70} {1,10}  last modified:{2}  age:{3}d" -f $_.Path, $_.SizeStr, $_.LastModified, $_.AgeDays) -ForegroundColor $color
}

# ============================================================
# SECTION 4 — DUPLICATE FILENAMES IN DOWNLOADS
# Files with (1), (2), Copy suffixes — usually forgotten duplicates
# ============================================================
Write-Host ""
Write-Host "=== LIKELY DUPLICATE FILES (in Downloads + Desktop) ===" -ForegroundColor Yellow
Write-Host ""

$dupPaths = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")
foreach ($dp in $dupPaths) {
    if (-not (Test-Path $dp)) { continue }
    Get-ChildItem $dp -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "\(\d+\)|\bcopy\b|copy of" -and $_.Length -ge $minBytes } |
        ForEach-Object {
            $color = if ($_.Length -gt 100MB) { "Red" } elseif ($_.Length -gt 10MB) { "Yellow" } else { "White" }
            Write-Host ("{0,-70} {1,10}" -f $_.FullName, (Format-Size $_.Length)) -ForegroundColor $color
        }
}

# ============================================================
# SECTION 5 — OLD INSTALLER FILES
# .exe, .msi, .zip, .7z, .iso not accessed in 180+ days
# ============================================================
Write-Host ""
Write-Host "=== OLD INSTALLER / ARCHIVE FILES NOT ACCESSED IN $DaysOld+ DAYS ===" -ForegroundColor Yellow
Write-Host ""

$installerExts = @(".exe", ".msi", ".zip", ".7z", ".iso", ".dmg", ".pkg", ".cab")
$installerPaths = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents")

$oldInstallers = @()
foreach ($ip in $installerPaths) {
    if (-not (Test-Path $ip)) { continue }
    Get-ChildItem $ip -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object {
            $installerExts -contains $_.Extension.ToLower() -and
            $_.LastAccessTime -lt $cutoff -and
            $_.Length -ge $minBytes
        } | ForEach-Object {
            $oldInstallers += [PSCustomObject]@{
                Path         = $_.FullName
                Size         = $_.Length
                SizeStr      = Format-Size $_.Length
                LastAccessed = $_.LastAccessTime.ToString("yyyy-MM-dd")
                AgeDays      = [int]($now - $_.LastAccessTime).TotalDays
            }
        }
}

$oldInstallers | Sort-Object Size -Descending | ForEach-Object {
    $color = if ($_.Size -gt 200MB) { "Red" } elseif ($_.Size -gt 50MB) { "Yellow" } else { "White" }
    Write-Host ("{0,-70} {1,10}  last:{2}" -f $_.Path, $_.SizeStr, $_.LastAccessed) -ForegroundColor $color
}
$instTotal = ($oldInstallers | Measure-Object -Property Size -Sum).Sum
Write-Host ""
Write-Host ("  Total: {0} files — {1}" -f $oldInstallers.Count, (Format-Size ([long]($instTotal ?? 0)))) -ForegroundColor Cyan

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  RED    = over 100 MB / 500 MB (folders)" -ForegroundColor Red
Write-Host "  YELLOW = over 10 MB / 50 MB (folders)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Re-run with different threshold:" -ForegroundColor Gray
Write-Host "    powershell -ExecutionPolicy Bypass -File .\find-stale-files.ps1 -DaysOld 90" -ForegroundColor Gray
Write-Host "    powershell -ExecutionPolicy Bypass -File .\find-stale-files.ps1 -DaysOld 365 -MinSizeMB 10" -ForegroundColor Gray
Write-Host ""
Write-Host "Scan complete." -ForegroundColor Green
