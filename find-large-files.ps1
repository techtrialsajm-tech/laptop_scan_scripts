# Storage Cleanup Finder - identifies large files/folders, especially Claude session data
# Run as: .\find-large-files.ps1

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

Write-Host "`n=== CLAUDE DESKTOP SESSION FILES ===" -ForegroundColor Cyan

$claudePaths = @(
    "$env:APPDATA\Claude",
    "$env:LOCALAPPDATA\Claude",
    "$env:APPDATA\Claude Desktop",
    "$env:LOCALAPPDATA\Claude Desktop",
    "$env:USERPROFILE\.claude",
    "$env:USERPROFILE\AppData\Roaming\Claude",
    "$env:USERPROFILE\AppData\Local\Programs\claude-desktop"
)

foreach ($p in $claudePaths) {
    if (Test-Path $p) {
        $size = Get-FolderSize $p
        Write-Host ("{0,-60} {1,10}" -f $p, (Format-Size $size)) -ForegroundColor Yellow
        # Show sub-breakdown
        Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
            $subSize = if ($_.PSIsContainer) { Get-FolderSize $_.FullName } else { $_.Length }
            if ($subSize -gt 1MB) {
                Write-Host ("  {0,-58} {1,10}" -f $_.Name, (Format-Size $subSize))
            }
        }
    }
}

Write-Host "`n=== TOP 20 LARGEST FOLDERS UNDER C:\Users\$env:USERNAME ===" -ForegroundColor Cyan

$topFolders = @(
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\Roaming",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop"
)

$results = @()
foreach ($base in $topFolders) {
    if (Test-Path $base) {
        Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $size = Get-FolderSize $_.FullName
            if ($size -gt 50MB) {
                $results += [PSCustomObject]@{ Path = $_.FullName; Size = $size; SizeStr = Format-Size $size }
            }
        }
    }
}
$results | Sort-Object Size -Descending | Select-Object -First 20 |
    ForEach-Object { Write-Host ("{0,-65} {1,10}" -f $_.Path, $_.SizeStr) }

Write-Host "`n=== COMMON SAFE-TO-DELETE LOCATIONS ===" -ForegroundColor Cyan

$cleanupTargets = @{
    "Windows Temp"              = $env:TEMP
    "Windows Temp (System)"     = "C:\Windows\Temp"
    "Prefetch"                  = "C:\Windows\Prefetch"
    "SoftwareDistribution Cache"= "C:\Windows\SoftwareDistribution\Download"
    "Thumbnails Cache"          = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    "Chrome Cache"              = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    "Edge Cache"                = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    "npm Cache"                 = "$env:LOCALAPPDATA\npm-cache"
    "pip Cache"                 = "$env:LOCALAPPDATA\pip\Cache"
    "VS Code Logs"              = "$env:APPDATA\Code\logs"
    "VS Code Cache"             = "$env:APPDATA\Code\CachedData"
    "node_modules (Downloads)"  = "$env:USERPROFILE\Downloads"
}

foreach ($label in $cleanupTargets.Keys) {
    $path = $cleanupTargets[$label]
    if (Test-Path $path) {
        $size = Get-FolderSize $path
        if ($size -gt 10MB) {
            Write-Host ("{0,-35} {1,-50} {2,10}" -f $label, $path, (Format-Size $size)) -ForegroundColor Green
        }
    }
}

Write-Host "`n=== TOP 20 LARGEST INDIVIDUAL FILES ON C:\ ===" -ForegroundColor Cyan
Write-Host "(scanning user profile only for speed...)" -ForegroundColor Gray

Get-ChildItem "$env:USERPROFILE" -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 100MB } |
    Sort-Object Length -Descending |
    Select-Object -First 20 |
    ForEach-Object {
        Write-Host ("{0,-75} {1,10}" -f $_.FullName, (Format-Size $_.Length))
    }

Write-Host "`n=== NODE_MODULES FOLDERS (can usually delete if project inactive) ===" -ForegroundColor Cyan
Get-ChildItem "$env:USERPROFILE" -Recurse -Force -Directory -Filter "node_modules" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $size = Get-FolderSize $_.FullName
        if ($size -gt 50MB) {
            Write-Host ("{0,-75} {1,10}" -f $_.FullName, (Format-Size $size)) -ForegroundColor Magenta
        }
    }

Write-Host "`nDone. Review above before deleting anything." -ForegroundColor White
