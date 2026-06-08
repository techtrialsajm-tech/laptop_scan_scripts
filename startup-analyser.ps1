# Startup & Boot Time Analyser
# Run as Administrator for full results

function Print-Header {
    param([string]$title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

# ============================================================
# SECTION 1 — LAST BOOT TIME & DURATION
# ============================================================
Print-Header "BOOT TIME"

$os = Get-CimInstance Win32_OperatingSystem
$lastBoot = $os.LastBootUpTime
Write-Host "  Last boot     : $lastBoot" -ForegroundColor White

# Windows event log boot duration
try {
    $bootEvent = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Diagnostics-Performance/Operational'; Id=100} -MaxEvents 1 -ErrorAction Stop
    $bootMs = ([xml]$bootEvent.ToXml()).Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' } | Select-Object -ExpandProperty '#text'
    Write-Host "  Last boot duration : $([math]::Round([int]$bootMs/1000, 1)) seconds" -ForegroundColor $(if ([int]$bootMs -gt 60000) {'Red'} elseif ([int]$bootMs -gt 30000) {'Yellow'} else {'Green'})
} catch {
    Write-Host "  Boot duration : (run as Admin to see)" -ForegroundColor Gray
}

# ============================================================
# SECTION 2 — STARTUP PROGRAMS
# ============================================================
Print-Header "STARTUP PROGRAMS (auto-launch on login)"

$startupItems = @()

# Registry - HKCU
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue |
    Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
        $val = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run").$($_.Name)
        $startupItems += [PSCustomObject]@{ Name = $_.Name; Command = $val; Source = "HKCU Run"; Safe = "" }
    }

# Registry - HKLM
Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue |
    Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
        $val = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run").$($_.Name)
        $startupItems += [PSCustomObject]@{ Name = $_.Name; Command = $val; Source = "HKLM Run"; Safe = "" }
    }

# Startup folders
$startupFolders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
)
foreach ($folder in $startupFolders) {
    if (Test-Path $folder) {
        Get-ChildItem $folder -ErrorAction SilentlyContinue | ForEach-Object {
            $startupItems += [PSCustomObject]@{ Name = $_.Name; Command = $_.FullName; Source = "Startup Folder"; Safe = "" }
        }
    }
}

# Known safe-to-disable patterns
$safeToDisable = @(
    "OneDrive", "Teams", "Slack", "Discord", "Spotify", "Steam",
    "EpicGamesLauncher", "Zoom", "Skype", "iTunesHelper", "ApplePush",
    "GoogleUpdate", "GoogleDrive", "Dropbox", "AdobeUpdate", "AcroTray",
    "McAfee", "ccleaner", "Cortana", "BingSvc", "GameBarPresenceWriter",
    "WebAdvisor", "ShadowPlay", "NvBridge", "RtkAudUService", "Realtek"
)

# Known must-keep patterns
$mustKeep = @(
    "SecurityHealth", "WindowsDefender", "MsMpEng", "Explorer",
    "ctfmon",  # Input method editor - needed for typing
    "NvDisplay", "igfxtray", "IntelHD"  # GPU drivers
)

Write-Host ""
Write-Host ("  {0,-35} {1,-15} {2}" -f "NAME", "SOURCE", "COMMAND") -ForegroundColor White
Write-Host ("  {0}" -f ("-" * 100))

foreach ($item in $startupItems) {
    $isSafe   = $safeToDisable | Where-Object { $item.Name -match $_ -or $item.Command -match $_ }
    $isKeep   = $mustKeep      | Where-Object { $item.Name -match $_ -or $item.Command -match $_ }
    $short    = if ($item.Command.Length -gt 60) { $item.Command.Substring(0,57) + "..." } else { $item.Command }

    if ($isKeep) {
        Write-Host ("  {0,-35} {1,-15} {2}" -f $item.Name, $item.Source, $short) -ForegroundColor Green
        Write-Host ("  >>> KEEP - system/driver component") -ForegroundColor DarkGreen
    } elseif ($isSafe) {
        Write-Host ("  {0,-35} {1,-15} {2}" -f $item.Name, $item.Source, $short) -ForegroundColor Yellow
        Write-Host ("  >>> SAFE TO DISABLE - app auto-start, launch manually when needed") -ForegroundColor DarkYellow
    } else {
        Write-Host ("  {0,-35} {1,-15} {2}" -f $item.Name, $item.Source, $short) -ForegroundColor White
        Write-Host ("  >>> REVIEW - unknown, check manually") -ForegroundColor Gray
    }
    Write-Host ""
}

# ============================================================
# SECTION 3 — AUTOMATIC SERVICES (slow boot if too many)
# ============================================================
Print-Header "AUTOMATIC-START SERVICES"

# Categorise services
$keepServices = @(
    "Audiosrv", "AudioEndpointBuilder",  # Sound
    "WinDefend", "WdNisSvc", "SecurityHealthService",  # Security
    "Dnscache", "Dhcp", "NlaSvc", "netprofm",  # Networking
    "W32Time",  # Time sync
    "PlugPlay",  # Hardware detection
    "EventLog",  # Event log
    "Power",     # Power management
    "Schedule",  # Task scheduler
    "Themes",    # Desktop themes
    "WlanSvc",   # WiFi
    "mpssvc",    # Windows Firewall
    "RpcSs", "RPCSS",  # RPC
    "CryptSvc",  # Cryptography
    "wuauserv",  # Windows Update
    "LanmanWorkstation", "LanmanServer",  # File sharing
    "BITS",      # Background transfer
    "gpsvc",     # Group Policy
    "ProfSvc",   # User profiles
    "UserManager" # User management
)

$slowServices = @(
    @{ Name = "DiagTrack";          Label = "Telemetry/Diagnostics";        Safe = $true  },
    @{ Name = "dmwappushservice";   Label = "WAP Push (telemetry)";         Safe = $true  },
    @{ Name = "WSearch";            Label = "Windows Search Indexer";       Safe = $true  },
    @{ Name = "SysMain";            Label = "Superfetch";                   Safe = $true  },
    @{ Name = "Fax";                Label = "Fax";                          Safe = $true  },
    @{ Name = "PrintNotify";        Label = "Printer notifications";        Safe = $false },
    @{ Name = "Spooler";            Label = "Print Spooler";                Safe = $false },
    @{ Name = "XblAuthManager";     Label = "Xbox Auth";                    Safe = $true  },
    @{ Name = "XblGameSave";        Label = "Xbox Game Save";               Safe = $true  },
    @{ Name = "XboxNetApiSvc";      Label = "Xbox Networking";              Safe = $true  },
    @{ Name = "XboxGipSvc";         Label = "Xbox Accessories";             Safe = $true  },
    @{ Name = "lfsvc";              Label = "Geolocation";                  Safe = $true  },
    @{ Name = "MapsBroker";         Label = "Downloaded Maps";              Safe = $true  },
    @{ Name = "RetailDemo";         Label = "Retail Demo";                  Safe = $true  },
    @{ Name = "RemoteRegistry";     Label = "Remote Registry";              Safe = $true  },
    @{ Name = "TabletInputService"; Label = "Touch Keyboard";               Safe = $false },
    @{ Name = "WerSvc";             Label = "Windows Error Reporting";      Safe = $true  },
    @{ Name = "wisvc";              Label = "Windows Insider Service";      Safe = $true  },
    @{ Name = "wlidsvc";            Label = "Microsoft Account Sign-in";    Safe = $false },
    @{ Name = "OneSyncSvc";         Label = "Sync Host (calendar/mail)";    Safe = $false },
    @{ Name = "TokenBroker";        Label = "Web Account Manager";          Safe = $false },
    @{ Name = "DusmSvc";            Label = "Data Usage";                   Safe = $true  },
    @{ Name = "icssvc";             Label = "Mobile Hotspot";               Safe = $true  },
    @{ Name = "PhoneSvc";           Label = "Phone Service";                Safe = $true  },
    @{ Name = "TapiSrv";            Label = "Telephony";                    Safe = $true  },
    @{ Name = "WMPNetworkSvc";      Label = "Windows Media Player Network"; Safe = $true  },
    @{ Name = "Mcx2Svc";            Label = "Windows Media Center";         Safe = $true  },
    @{ Name = "irmon";              Label = "Infrared Monitor";             Safe = $true  },
    @{ Name = "SharedAccess";       Label = "Internet Connection Sharing";  Safe = $true  }
)

Write-Host ""
Write-Host ("  {0,-30} {1,-35} {1,-10} {2}" -f "SERVICE", "DESCRIPTION", "STATUS") -ForegroundColor White
Write-Host ("  {0}" -f ("-" * 90))

foreach ($entry in $slowServices) {
    $svc = Get-Service $entry.Name -ErrorAction SilentlyContinue
    if ($svc) {
        $color  = if ($entry.Safe) { "Yellow" } else { "White" }
        $action = if ($entry.Safe) { "SAFE TO DISABLE" } else { "REVIEW - may need it" }
        $status = "{0} / {1}" -f $svc.Status, $svc.StartType
        Write-Host ("  {0,-30} {1,-35} {2}" -f $svc.Name, $entry.Label, $status) -ForegroundColor $color
        Write-Host ("  >>> $action") -ForegroundColor $(if ($entry.Safe) { "DarkYellow" } else { "Gray" })
        Write-Host ""
    }
}

# ============================================================
# SECTION 4 — BOOT CRITICAL PATH (what's delaying boot)
# ============================================================
Print-Header "BOOT DELAY EVENTS (top slowest from event log)"

try {
    $perfEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
        Id      = @(101, 102, 103, 104)
    } -MaxEvents 20 -ErrorAction Stop

    $perfEvents | ForEach-Object {
        $xml  = [xml]$_.ToXml()
        $data = $xml.Event.EventData.Data
        $name = ($data | Where-Object { $_.Name -eq 'FileName' -or $_.Name -eq 'ServiceName' }).'#text'
        $dur  = ($data | Where-Object { $_.Name -eq 'Duration' }).'#text'
        if ($name -and $dur) {
            $durSec = [math]::Round([int]$dur / 1000, 1)
            $color  = if ($durSec -gt 5) { "Red" } elseif ($durSec -gt 2) { "Yellow" } else { "White" }
            Write-Host ("  {0,-55} {1,6}s  ID:{2}" -f $name, $durSec, $_.Id) -ForegroundColor $color
        }
    }
} catch {
    Write-Host "  Run as Administrator to see boot delay events" -ForegroundColor Gray
}

# ============================================================
# SECTION 5 — QUICK WINS SUMMARY
# ============================================================
Print-Header "QUICK WINS SUMMARY"

Write-Host "  To disable safe startup services, run as Admin:" -ForegroundColor White
Write-Host ""

$toDisable = $slowServices | Where-Object { $_.Safe }
foreach ($entry in $toDisable) {
    $svc = Get-Service $entry.Name -ErrorAction SilentlyContinue
    if ($svc -and $svc.StartType -ne "Disabled") {
        Write-Host ("  Stop-Service '{0}' -Force -ErrorAction SilentlyContinue" -f $entry.Name)
        Write-Host ("  Set-Service  '{0}' -StartupType Disabled" -f $entry.Name)
        Write-Host ""
    }
}

Write-Host "  To manage startup programs:" -ForegroundColor Cyan
Write-Host "    Task Manager > Startup tab (Ctrl+Shift+Esc)"
Write-Host "    OR: Settings > Apps > Startup"
Write-Host ""
Write-Host "Scan complete." -ForegroundColor Green
