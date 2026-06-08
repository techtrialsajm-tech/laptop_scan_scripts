# Defender diagnostic + fix script - Run as Administrator

Write-Host ""
Write-Host "=== CURRENT STATE ===" -ForegroundColor Cyan

# Check service status
$svc = Get-Service WinDefend -ErrorAction SilentlyContinue
Write-Host ("WinDefend service status   : {0}" -f $svc.Status)
Write-Host ("WinDefend startup type     : {0}" -f $svc.StartType)

# Check registry keys
Write-Host ""
Write-Host "--- Registry: Policies blocking Defender ---" -ForegroundColor Yellow
$policyKeys = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection",
    "HKLM:\SOFTWARE\Microsoft\Windows Defender"
)
foreach ($key in $policyKeys) {
    if (Test-Path $key) {
        Write-Host "Key exists: $key" -ForegroundColor White
        Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Select-Object * -ExcludeProperty PS* |
            Format-List
    }
}

# Check WinDefend service registry
Write-Host "--- WinDefend service registry start value ---" -ForegroundColor Yellow
$startVal = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name Start -ErrorAction SilentlyContinue).Start
Write-Host ("Start value: {0} (2=Auto, 3=Manual, 4=Disabled)" -f $startVal)

Write-Host ""
Write-Host "=== ATTEMPTING FIXES ===" -ForegroundColor Cyan

# Fix 1: Remove all blocking policy keys
Write-Host "Removing policy blocks..." -ForegroundColor Yellow
$valuesToDelete = @(
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"; Name = "DisableAntiSpyware" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"; Name = "DisableAntiVirus" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"; Name = "DisableRealtimeMonitoring" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"; Name = "DisableBehaviorMonitoring" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"; Name = "DisableOnAccessProtection" }
)
foreach ($item in $valuesToDelete) {
    if (Test-Path $item.Path) {
        Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue
        Write-Host ("  Removed: {0}\{1}" -f $item.Path, $item.Name)
    }
}

# Fix 2: Set service start type via registry (bypasses Set-Service permission issue)
Write-Host "Setting WinDefend start type to Automatic via registry..." -ForegroundColor Yellow
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WinDefend" /v "Start" /t REG_DWORD /d 2 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WdNisSvc" /v "Start" /t REG_DWORD /d 3 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WdFilter" /v "Start" /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WdBoot" /v "Start" /t REG_DWORD /d 0 /f

# Fix 3: Try starting the service now
Write-Host "Starting WinDefend service..." -ForegroundColor Yellow
Start-Service WinDefend -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$svc2 = Get-Service WinDefend -ErrorAction SilentlyContinue
Write-Host ("WinDefend status after fix : {0}" -f $svc2.Status)

# Fix 4: Try enabling real-time protection
Write-Host "Enabling real-time protection..." -ForegroundColor Yellow
try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Write-Host "SUCCESS - real-time protection enabled" -ForegroundColor Green
} catch {
    Write-Host ("FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host "A reboot is required for registry changes to take effect." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== FINAL STATUS ===" -ForegroundColor Cyan
try {
    $status = Get-MpComputerStatus -ErrorAction Stop
    Write-Host ("Antivirus enabled        : {0}" -f $status.AntivirusEnabled) -ForegroundColor $(if ($status.AntivirusEnabled) {"Green"} else {"Red"})
    Write-Host ("Real-time protection     : {0}" -f $status.RealTimeProtectionEnabled) -ForegroundColor $(if ($status.RealTimeProtectionEnabled) {"Green"} else {"Red"})
} catch {
    Write-Host "Cannot get status yet - reboot required" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "If still failing after this script, run: sfc /scannow" -ForegroundColor Gray
Write-Host "Then reboot and check Windows Security app manually." -ForegroundColor Gray
