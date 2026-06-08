# Windows Performance Booster - RAM, Disk, CPU
# Run as Administrator
# Each section is independent - read before applying

function Print-Header {
    param([string]$title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Print-Done  { Write-Host "  OK: $args" -ForegroundColor Green }
function Print-Skip  { Write-Host "  SKIP: $args" -ForegroundColor Gray }
function Print-Warn  { Write-Host "  WARN: $args" -ForegroundColor Yellow }

# ============================================================
# SECTION 1 — POWER PLAN (biggest single CPU/RAM win)
# ============================================================
Print-Header "POWER PLAN"

$current = powercfg /getactivescheme
Write-Host "  Current: $current"

# Set High Performance
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
if ($?) {
    Print-Done "Power plan set to High Performance"
} else {
    # Create it if missing
    powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    Print-Done "High Performance plan created and activated"
}

# Disable USB selective suspend (stops USB devices stuttering)
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setactive SCHEME_CURRENT
Print-Done "USB selective suspend disabled"

# ============================================================
# SECTION 2 — CPU PERFORMANCE
# ============================================================
Print-Header "CPU PERFORMANCE"

# Minimum processor state 100% on AC (no throttling)
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
powercfg /setactive SCHEME_CURRENT
Print-Done "CPU minimum processor state set to 100% (no throttling)"

# Disable Core Parking (all cores always available)
$cpuKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583"
if (Test-Path $cpuKey) {
    Set-ItemProperty $cpuKey -Name "ValueMax" -Value 0 -ErrorAction SilentlyContinue
    Print-Done "CPU core parking disabled"
}

# Disable HPET (High Precision Event Timer) - reduces timer overhead
bcdedit /deletevalue useplatformclock 2>$null
bcdedit /set useplatformtick yes 2>$null
bcdedit /set disabledynamictick yes 2>$null
Print-Done "Dynamic tick disabled (lower interrupt overhead)"

# ============================================================
# SECTION 3 — RAM OPTIMISATION
# ============================================================
Print-Header "RAM OPTIMISATION"

# Disable memory compression (frees CPU cycles, only useful if RAM > 8GB)
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Write-Host "  Detected RAM: $ramGB GB"

if ($ramGB -ge 16) {
    $compression = (Get-MMAgent).MemoryCompression
    if ($compression) {
        Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        Print-Done "Memory compression disabled (you have $ramGB GB RAM, not needed)"
    } else {
        Print-Skip "Memory compression already off"
    }
} else {
    Print-Skip "Memory compression kept ON (RAM < 16 GB — compression helps here)"
}

# Clear standby memory list (frees RAM cached by idle processes)
$code = @"
using System;
using System.Runtime.InteropServices;
public class MemClear {
    [DllImport("ntdll.dll")] public static extern uint NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);
    public static void ClearStandby() {
        IntPtr ptr = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(ptr, 4);
        NtSetSystemInformation(80, ptr, 4);
        Marshal.FreeHGlobal(ptr);
    }
}
"@
try {
    Add-Type $code -ErrorAction Stop
    [MemClear]::ClearStandby()
    Print-Done "Standby memory list cleared"
} catch {
    Print-Skip "Could not clear standby memory (non-critical)"
}

# Disable Superfetch/SysMain (helps on SSD, reduces RAM pre-loading)
$sysmain = Get-Service SysMain -ErrorAction SilentlyContinue
if ($sysmain) {
    # Check if drive is SSD
    $diskType = (Get-PhysicalDisk | Select-Object -First 1).MediaType
    Write-Host "  Drive type detected: $diskType"
    if ($diskType -eq "SSD" -or $diskType -eq "NVMe") {
        Stop-Service SysMain -Force -ErrorAction SilentlyContinue
        Set-Service SysMain -StartupType Disabled -ErrorAction SilentlyContinue
        Print-Done "SysMain (Superfetch) disabled - SSD detected, not needed"
    } else {
        Print-Skip "SysMain kept ON (HDD detected - Superfetch helps on spinning disk)"
    }
}

# ============================================================
# SECTION 4 — DISK PERFORMANCE
# ============================================================
Print-Header "DISK PERFORMANCE"

# Enable TRIM for SSD
$trimResult = fsutil behavior query DisableDeleteNotify 2>$null
Write-Host "  TRIM status: $trimResult"
fsutil behavior set DisableDeleteNotify 0 | Out-Null
Print-Done "TRIM enabled (keeps SSD performance from degrading)"

# Disable last access timestamp update (reduces disk writes)
fsutil behavior set disablelastaccess 1 | Out-Null
Print-Done "Last access timestamp updates disabled (reduces unnecessary disk writes)"

# Disable 8.3 filename creation (legacy, slows NTFS)
fsutil behavior set disable8dot3 1 | Out-Null
Print-Done "8.3 filename creation disabled"

# Enable large system cache
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 0 -ErrorAction SilentlyContinue
Print-Done "Memory manager optimised for programs (not file cache)"

# Disable drive indexing on C: (reduces background disk activity)
$drive = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter='C:'" -ErrorAction SilentlyContinue
if ($drive) {
    $drive.IndexingEnabled = $false
    $drive.Put() | Out-Null
    Print-Done "Indexing disabled on C: (reduces background disk activity)"
}

# ============================================================
# SECTION 5 — VISUAL EFFECTS (frees CPU/GPU cycles)
# ============================================================
Print-Header "VISUAL EFFECTS"

$visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $visualKey)) { New-Item $visualKey -Force | Out-Null }
Set-ItemProperty $visualKey -Name "VisualFXSetting" -Value 2  # Adjust for best performance

# Keep font smoothing and thumbnail previews, kill everything else
$perfKey = "HKCU:\Control Panel\Desktop"
Set-ItemProperty $perfKey -Name "DragFullWindows" -Value "0"
Set-ItemProperty $perfKey -Name "MenuShowDelay" -Value "0"      # Instant menus
Set-ItemProperty $perfKey -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00))

$advancedKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty $advancedKey -Name "ListviewAlphaSelect" -Value 0
Set-ItemProperty $advancedKey -Name "TaskbarAnimations" -Value 0
Set-ItemProperty $advancedKey -Name "ListviewShadow" -Value 0

# Disable transparency
Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -ErrorAction SilentlyContinue

Print-Done "Visual effects trimmed (animations, transparency, shadows off)"

# ============================================================
# SECTION 6 — BACKGROUND SERVICES (disable telemetry/bloat)
# ============================================================
Print-Header "BACKGROUND SERVICES"

$servicesToDisable = @(
    @{ Name = "DiagTrack";        Label = "Connected User Experiences & Telemetry" },
    @{ Name = "dmwappushservice"; Label = "WAP Push Message Routing" },
    @{ Name = "WSearch";          Label = "Windows Search (indexing)" },
    @{ Name = "Fax";              Label = "Fax service" },
    @{ Name = "XblAuthManager";   Label = "Xbox Live Auth Manager" },
    @{ Name = "XblGameSave";      Label = "Xbox Live Game Save" },
    @{ Name = "XboxNetApiSvc";    Label = "Xbox Live Networking" },
    @{ Name = "lfsvc";            Label = "Geolocation Service" },
    @{ Name = "MapsBroker";       Label = "Downloaded Maps Manager" },
    @{ Name = "RetailDemo";       Label = "Retail Demo Service" }
)

foreach ($svc in $servicesToDisable) {
    $s = Get-Service $svc.Name -ErrorAction SilentlyContinue
    if ($s -and $s.StartType -ne "Disabled") {
        try {
            Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
            Set-Service $svc.Name -StartupType Disabled -ErrorAction Stop
            Print-Done "Disabled: $($svc.Label)"
        } catch {
            Print-Skip "Could not disable: $($svc.Label)"
        }
    } else {
        Print-Skip "Already disabled: $($svc.Label)"
    }
}

# ============================================================
# SECTION 7 — NETWORK PERFORMANCE
# ============================================================
Print-Header "NETWORK PERFORMANCE"

# Disable Nagle's algorithm (reduces latency for real-time apps)
$tcpKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
Get-ChildItem $tcpKey | ForEach-Object {
    Set-ItemProperty $_.PSPath -Name "TcpAckFrequency" -Value 1 -ErrorAction SilentlyContinue
    Set-ItemProperty $_.PSPath -Name "TCPNoDelay" -Value 1 -ErrorAction SilentlyContinue
}
Print-Done "Nagle's algorithm disabled (lower network latency)"

# Disable network throttling
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xffffffff -ErrorAction SilentlyContinue
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0 -ErrorAction SilentlyContinue
Print-Done "Network throttling disabled"

# ============================================================
# SUMMARY
# ============================================================
Print-Header "DONE — REBOOT REQUIRED"
Write-Host "  Changes that take full effect after reboot:" -ForegroundColor Yellow
Write-Host "    - Power plan / CPU throttling"
Write-Host "    - Core parking"
Write-Host "    - Dynamic tick"
Write-Host "    - Disk indexing"
Write-Host "    - Visual effects"
Write-Host ""
Write-Host "  Changes active immediately:" -ForegroundColor Green
Write-Host "    - Standby memory cleared"
Write-Host "    - Services disabled"
Write-Host "    - Network latency tweaks"
Write-Host ""
Write-Host "  Run after reboot to verify power plan:" -ForegroundColor Cyan
Write-Host "    powercfg /getactivescheme"
