# Full C: Drive Storage Scanner
# Run as Administrator for best results
# Usage: powershell -ExecutionPolicy Bypass -File .\full-scan.ps1

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

# ============================================================
# SECTION 1: SAFE-TO-DELETE FOLDERS (priority list)
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SAFE-TO-DELETE FOLDERS (common cleanup targets)"           -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$safeTargets = [ordered]@{
    # Windows junk
    "Windows Temp"                    = "C:\Windows\Temp"
    "User Temp"                       = "$env:TEMP"
    "Windows Error Reports"           = "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"
    "Windows Error Archive"           = "C:\ProgramData\Microsoft\Windows\WER\ReportArchive"
    "Windows Update Cache"            = "C:\Windows\SoftwareDistribution\Download"
    "Prefetch"                        = "C:\Windows\Prefetch"
    "Delivery Optimisation Cache"     = "C:\Windows\SoftwareDistribution\DeliveryOptimization"
    "Crash Dumps"                     = "C:\Windows\Minidump"
    "Recycle Bin"                     = "C:\`$Recycle.Bin"

    # Browser caches
    "Chrome Cache"                    = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    "Chrome GPU Cache"                = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
    "Chrome Code Cache"               = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
    "Edge Cache"                      = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    "Edge GPU Cache"                  = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
    "Firefox Cache"                   = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    "IE/Legacy Cache"                 = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"

    # Dev tool caches
    "npm Cache"                       = "$env:LOCALAPPDATA\npm-cache"
    "yarn Cache"                      = "$env:LOCALAPPDATA\Yarn\Cache"
    "pip Cache"                       = "$env:LOCALAPPDATA\pip\Cache"
    "NuGet Cache"                     = "$env:LOCALAPPDATA\NuGet\Cache"
    "Gradle Cache"                    = "$env:USERPROFILE\.gradle\caches"
    "Maven Cache"                     = "$env:USERPROFILE\.m2\repository"
    "Cargo Registry"                  = "$env:USERPROFILE\.cargo\registry"
    "Go Module Cache"                 = "$env:USERPROFILE\go\pkg\mod"
    "Docker Desktop Images"           = "$env:LOCALAPPDATA\Docker\wsl"

    # VS Code / IDEs
    "VS Code Logs"                    = "$env:APPDATA\Code\logs"
    "VS Code CachedData"              = "$env:APPDATA\Code\CachedData"
    "VS Code CachedExtensions"        = "$env:APPDATA\Code\CachedExtensions"
    "JetBrains Logs"                  = "$env:LOCALAPPDATA\JetBrains"

    # AI / Claude specific
    "Claude VM backup (.zst files)"   = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\vm_bundles"
    "Claude Logs"                     = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\logs"
    "Claude Session Transcripts"      = "$env:USERPROFILE\.claude\projects"

    # Windows Store app caches
    "Windows Store Cache"             = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"

    # Misc
    "Thumbnail Cache"                 = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    "Font Cache"                      = "$env:LOCALAPPDATA\Microsoft\Windows\FontCache"
    "Teams Cache"                     = "$env:APPDATA\Microsoft\Teams\Cache"
    "Teams GPU Cache"                 = "$env:APPDATA\Microsoft\Teams\GPUCache"
    "Zoom Cache"                      = "$env:APPDATA\Zoom\data"
    "Spotify Cache"                   = "$env:LOCALAPPDATA\Spotify\Data"
    "Discord Cache"                   = "$env:APPDATA\discord\Cache"
    "Slack Cache"                     = "$env:APPDATA\Slack\Cache"
    "OneDrive Temp"                   = "$env:LOCALAPPDATA\Microsoft\OneDrive\logs"
    "Downloaded Installers"           = "$env:LOCALAPPDATA\Downloaded Installations"
    "Windows Installer Patch Cache"   = "C:\Windows\Installer\`$PatchCache`$"
}

$totalSafe = 0
foreach ($label in $safeTargets.Keys) {
    $path = $safeTargets[$label]
    if (Test-Path $path) {
        $size = Get-FolderSize $path
        if ($size -gt 1MB) {
            $totalSafe += $size
            $color = if ($size -gt 1GB) { "Red" } elseif ($size -gt 200MB) { "Yellow" } else { "Green" }
            Write-Host ("{0,-40} {1,-55} {2,10}" -f $label, $path, (Format-Size $size)) -ForegroundColor $color
        }
    }
}
Write-Host ""
Write-Host ("  TOTAL RECOVERABLE FROM ABOVE: {0}" -f (Format-Size $totalSafe)) -ForegroundColor Cyan

# ============================================================
# SECTION 2: TOP 30 LARGEST FILES ON C:\
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TOP 30 LARGEST FILES ON C:\"                               -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "(this may take a few minutes...)" -ForegroundColor Gray

$skipPaths = @(
    "C:\Windows\WinSxS",
    "C:\System Volume Information",
    "C:\Recovery"
)

$largeFiles = Get-ChildItem "C:\" -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object {
        $file = $_
        $skip = $false
        foreach ($s in $skipPaths) { if ($file.FullName.StartsWith($s)) { $skip = $true; break } }
        -not $skip -and $file.Length -gt 50MB
    } |
    Sort-Object Length -Descending |
    Select-Object -First 30

foreach ($f in $largeFiles) {
    $color = if ($f.Length -gt 1GB) { "Red" } elseif ($f.Length -gt 200MB) { "Yellow" } else { "White" }
    Write-Host ("{0,-80} {1,10}" -f $f.FullName, (Format-Size $f.Length)) -ForegroundColor $color
}

# ============================================================
# SECTION 3: TOP 30 LARGEST FOLDERS ON C:\
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TOP 30 LARGEST FOLDERS (2-3 levels deep)"                  -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$scanRoots = @(
    "C:\Users\$env:USERNAME\AppData\Local",
    "C:\Users\$env:USERNAME\AppData\Roaming",
    "C:\Users\$env:USERNAME\Downloads",
    "C:\Users\$env:USERNAME\Documents",
    "C:\Users\$env:USERNAME\Desktop",
    "C:\Program Files",
    "C:\Program Files (x86)",
    "C:\ProgramData"
)

$folderResults = @()
foreach ($root in $scanRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $size = Get-FolderSize $_.FullName
        if ($size -gt 100MB) {
            $folderResults += [PSCustomObject]@{ Path = $_.FullName; Size = $size }
        }
        # One level deeper
        Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $subSize = Get-FolderSize $_.FullName
            if ($subSize -gt 100MB) {
                $folderResults += [PSCustomObject]@{ Path = $_.FullName; Size = $subSize }
            }
        }
    }
}

$folderResults | Sort-Object Size -Descending | Select-Object -First 30 | ForEach-Object {
    $color = if ($_.Size -gt 5GB) { "Red" } elseif ($_.Size -gt 1GB) { "Yellow" } else { "White" }
    Write-Host ("{0,-80} {1,10}" -f $_.Path, (Format-Size $_.Size)) -ForegroundColor $color
}

# ============================================================
# SECTION 4: node_modules FOLDERS
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " node_modules FOLDERS (safe to delete if project inactive)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Get-ChildItem "C:\Users\$env:USERNAME" -Recurse -Force -Directory -Filter "node_modules" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $size = Get-FolderSize $_.FullName
        if ($size -gt 10MB) {
            Write-Host ("{0,-80} {1,10}" -f $_.FullName, (Format-Size $size)) -ForegroundColor Magenta
        }
    }

Write-Host ""
Write-Host "Scan complete." -ForegroundColor Green
Write-Host "RED   = over 1 GB" -ForegroundColor Red
Write-Host "YELLOW= over 200 MB" -ForegroundColor Yellow
Write-Host "GREEN = smaller but worth cleaning" -ForegroundColor Green
