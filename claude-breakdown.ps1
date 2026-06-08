function Get-FolderSize {
    param([string]$path)
    try {
        $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                 Where-Object { -not $_.PSIsContainer } |
                 Measure-Object -Property Length -Sum).Sum
        if ($size) { return [long]$size } else { return 0 }
    } catch { return 0 }
}
function Format-Size {
    param([long]$bytes)
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    return "{0:N2} KB" -f ($bytes / 1KB)
}

$base = "C:\Users\anton\AppData\Local\Packages\Claude_pzs8sxrjxfjjc"

Write-Host "=== CLAUDE PACKAGE ROOT ===" -ForegroundColor Cyan
$total = Get-FolderSize $base
Write-Host "Total: $(Format-Size $total)" -ForegroundColor Yellow

Write-Host ""
Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
    $size = if ($_.PSIsContainer) { Get-FolderSize $_.FullName } else { $_.Length }
    Write-Host ("{0,-50} {1,10}" -f $_.Name, (Format-Size $size))
}

Write-Host ""
Write-Host "=== LocalCache\Roaming\Claude (deep breakdown) ===" -ForegroundColor Cyan
$roaming = "$base\LocalCache\Roaming\Claude"

if (Test-Path $roaming) {
    Get-ChildItem $roaming -ErrorAction SilentlyContinue | ForEach-Object {
        $size = if ($_.PSIsContainer) { Get-FolderSize $_.FullName } else { $_.Length }
        Write-Host ("{0,-55} {1,10}" -f $_.Name, (Format-Size $size)) -ForegroundColor White

        if ($_.PSIsContainer) {
            Get-ChildItem $_.FullName -ErrorAction SilentlyContinue | ForEach-Object {
                $subSize = if ($_.PSIsContainer) { Get-FolderSize $_.FullName } else { $_.Length }
                Write-Host ("  {0,-53} {1,10}" -f $_.Name, (Format-Size $subSize))

                if ($_.PSIsContainer) {
                    Get-ChildItem $_.FullName -ErrorAction SilentlyContinue | ForEach-Object {
                        $subSubSize = if ($_.PSIsContainer) { Get-FolderSize $_.FullName } else { $_.Length }
                        Write-Host ("    {0,-51} {1,10}" -f $_.Name, (Format-Size $subSubSize))
                    }
                }
            }
        }
    }
}

Write-Host ""
Write-Host "=== LocalCache\Local (deep breakdown) ===" -ForegroundColor Cyan
$local = "$base\LocalCache\Local"
if (Test-Path $local) {
    Get-ChildItem $local -Recurse -ErrorAction SilentlyContinue -Directory | ForEach-Object {
        $depth = ($_.FullName -split "\\").Count - ($local -split "\\").Count
        if ($depth -le 3) {
            $size = Get-FolderSize $_.FullName
            if ($size -gt 5MB) {
                $indent = "  " * $depth
                Write-Host ("{0}{1,-55} {2,10}" -f $indent, $_.Name, (Format-Size $size))
            }
        }
    }
}
