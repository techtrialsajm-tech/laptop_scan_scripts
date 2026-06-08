# Check if any Dell processes, services or installed programs still exist

Write-Host ""
Write-Host "=== DELL INSTALLED PROGRAMS ===" -ForegroundColor Cyan
$dell = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                         "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "dell" }
if ($dell) {
    $dell | Select-Object DisplayName, DisplayVersion | Format-Table -AutoSize
} else {
    Write-Host "  No Dell programs found in registry" -ForegroundColor Green
}

Write-Host "=== DELL RUNNING PROCESSES ===" -ForegroundColor Cyan
$procs = Get-Process | Where-Object { $_.Name -match "dell" -or $_.Path -match "dell" }
if ($procs) {
    $procs | Select-Object Name, Id, Path | Format-Table -AutoSize
} else {
    Write-Host "  No Dell processes running" -ForegroundColor Green
}

Write-Host "=== DELL SERVICES ===" -ForegroundColor Cyan
$svcs = Get-Service | Where-Object { $_.DisplayName -match "dell" -or $_.Name -match "dell" }
if ($svcs) {
    $svcs | Select-Object DisplayName, Name, Status | Format-Table -AutoSize
} else {
    Write-Host "  No Dell services found" -ForegroundColor Green
}

Write-Host "=== DELL SCHEDULED TASKS ===" -ForegroundColor Cyan
$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -match "dell" -or $_.TaskPath -match "dell" } -ErrorAction SilentlyContinue
if ($tasks) {
    $tasks | Select-Object TaskName, TaskPath, State | Format-Table -AutoSize
} else {
    Write-Host "  No Dell scheduled tasks found" -ForegroundColor Green
}

Write-Host "=== DELL PROGRAM FILES ===" -ForegroundColor Cyan
$paths = @("C:\Program Files\Dell", "C:\Program Files (x86)\Dell")
foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Host "  Still exists: $p" -ForegroundColor Yellow
    } else {
        Write-Host "  Gone: $p" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== VERDICT ===" -ForegroundColor Cyan
$anyDell = $dell -or $procs -or $svcs -or $tasks
if (-not $anyDell) {
    Write-Host "  All clear - C:\ProgramData\Dell is safe to delete" -ForegroundColor Green
} else {
    Write-Host "  Dell still has active components - review above before deleting" -ForegroundColor Yellow
}
