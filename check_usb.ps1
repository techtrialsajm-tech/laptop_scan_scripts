# check_usb.ps1 - Show all connected USB/removable drives and their speeds

Write-Host "`n=== Connected Drives ===" -ForegroundColor Cyan

Get-Disk | ForEach-Object {
    $disk = $_
    $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    $volumes = $partitions | ForEach-Object { Get-Volume -Partition $_ -ErrorAction SilentlyContinue }

    [PSCustomObject]@{
        "#"        = $disk.Number
        Name       = $disk.FriendlyName
        Bus        = $disk.BusType
        "Size GB"  = [math]::Round($disk.Size / 1GB, 1)
        Health     = $disk.HealthStatus
        Letters    = ($volumes.DriveLetter -join ", ")
        Labels     = ($volumes.FileSystemLabel -join ", ")
        "Free GB"  = ($volumes | Measure-Object -Property SizeRemaining -Sum | ForEach-Object { [math]::Round($_.Sum / 1GB, 1) })
    }
} | Format-Table -AutoSize

Write-Host "`n=== USB Host Controllers ===" -ForegroundColor Cyan
Get-PnpDevice -Class USB -Status OK |
    Where-Object { $_.FriendlyName -match 'Host Controller|Root Hub' } |
    Select-Object FriendlyName |
    Format-Table -AutoSize

Write-Host "`n=== USB Speed Capability ===" -ForegroundColor Cyan
$controllers = Get-PnpDevice -Class USB -Status OK |
    Where-Object { $_.FriendlyName -match 'Host Controller' }

foreach ($c in $controllers) {
    $name = $c.FriendlyName
    $speed = if ($name -match '3\.1|3\.2|Gen 2')  { "USB 3.1/3.2  ~  up to 1250 MB/s" }
             elseif ($name -match '3\.0|3\.')       { "USB 3.0      ~  up to  400 MB/s" }
             elseif ($name -match '2\.0')            { "USB 2.0      ~  up to   60 MB/s" }
             else                                    { "Unknown" }
    Write-Host "  $name  -->  $speed"
}

Write-Host ""
