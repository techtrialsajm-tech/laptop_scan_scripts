# Check active antivirus and security software status

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ACTIVE ANTIVIRUS / SECURITY SOFTWARE"                       -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Method 1: Windows Security Center (most reliable)
Write-Host ""
Write-Host "--- Windows Security Center registered products ---" -ForegroundColor Yellow
try {
    $av = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop
    foreach ($a in $av) {
        $state = $a.productState
        # Decode productState bitmask
        $enabled  = [bool](($state -band 0x1000) -ne 0)
        $uptodate = [bool](($state -band 0x10)   -eq 0)
        Write-Host ("  Name       : {0}" -f $a.displayName) -ForegroundColor White
        Write-Host ("  Enabled    : {0}" -f $enabled)
        Write-Host ("  Up to date : {0}" -f $uptodate)
        Write-Host ("  State code : {0}" -f $state)
        Write-Host ""
    }
} catch {
    Write-Host "  Could not query SecurityCenter2 (try running as Admin)" -ForegroundColor Red
}

# Method 2: Check running services related to AV
Write-Host "--- Security-related RUNNING services ---" -ForegroundColor Yellow
$secServices = @(
    "MsMpSvc",        # Windows Defender
    "WinDefend",      # Windows Defender
    "Sense",          # Microsoft Defender ATP
    "mcshield",       # McAfee
    "mfemms",         # McAfee
    "mfevtp",         # McAfee
    "McTaskManager",  # McAfee
    "masvc",          # McAfee Agent
    "kvoop",          # McAfee
    "TmListenerSvc",  # Trend Micro
    "ekrn",           # ESET
    "avgsvc",         # AVG
    "avp",            # Kaspersky
    "NortonSecurity", # Norton
    "ns",             # Norton
    "SAVService",     # Sophos
    "SophosFIM",      # Sophos
    "bdagent",        # Bitdefender
    "MBAMService"     # Malwarebytes
)

$found = $false
foreach ($svc in $secServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        $color = if ($s.Status -eq "Running") { "Green" } else { "Gray" }
        Write-Host ("  {0,-20} Status: {1}" -f $s.DisplayName, $s.Status) -ForegroundColor $color
        $found = $true
    }
}
if (-not $found) { Write-Host "  None of the known AV services found running" -ForegroundColor Gray }

# Method 3: Check installed programs for McAfee/AV
Write-Host ""
Write-Host "--- Installed programs matching security/AV keywords ---" -ForegroundColor Yellow
$avKeywords = "mcafee|norton|avast|avg|kaspersky|bitdefender|malwarebytes|eset|trend micro|sophos|webroot|cylance|crowdstrike|sentinel|defender"
Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                 "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match $avKeywords } |
    Select-Object DisplayName, DisplayVersion, InstallDate |
    Format-Table -AutoSize

# Method 4: Windows Defender status
Write-Host "--- Windows Defender status ---" -ForegroundColor Yellow
try {
    $wd = Get-MpComputerStatus -ErrorAction Stop
    Write-Host ("  Defender enabled        : {0}" -f $wd.AntivirusEnabled)
    Write-Host ("  Real-time protection    : {0}" -f $wd.RealTimeProtectionEnabled)
    Write-Host ("  Last scan               : {0}" -f $wd.LastQuickScanEndTime)
    Write-Host ("  Definitions updated     : {0}" -f $wd.AntivirusSignatureLastUpdated)
} catch {
    Write-Host "  Could not get Defender status (may not be active)" -ForegroundColor Gray
}

# Method 5: McAfee specific — is anything actually running?
Write-Host ""
Write-Host "--- McAfee processes currently running ---" -ForegroundColor Yellow
$mcafeeProcs = Get-Process | Where-Object { $_.Name -match "mcafee|mfe|mcs|mcui|mcods" }
if ($mcafeeProcs) {
    $mcafeeProcs | Select-Object Name, Id, CPU | Format-Table -AutoSize
} else {
    Write-Host "  No McAfee processes currently running" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
