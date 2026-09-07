#Requires -Version 5.1
# TR-100 Machine Report (Windows / PowerShell port)
# Copyright (c) 2024, U.S. Graphics, LLC. BSD-3-Clause License.
# Ported to native Windows PowerShell. Edit this file directly to customize it.

# Render box-drawing and bar glyphs correctly on legacy conhost too.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---------------------------------------------------------------------------
# Global layout constants (same values as the original bash script)
# ---------------------------------------------------------------------------
$MinNameLen        = 5
$MaxNameLen        = 13
$MinDataLen        = 20
$MaxDataLen        = 32
$BordersAndPadding = 7

# ---------------------------------------------------------------------------
# Basic configuration, change as needed
# ---------------------------------------------------------------------------
$ReportTitle = "UNITED STATES GRAPHICS COMPANY"
$VolumeDrive = "C:"

# ---------------------------------------------------------------------------
# Box-drawing / bar glyphs (defined by code point so the source stays ASCII
# and reads correctly under any .ps1 file encoding)
# ---------------------------------------------------------------------------
$chH     = [string][char]0x2500  # horizontal
$chV     = [string][char]0x2502  # vertical
$chTL    = [string][char]0x250C  # top-left corner
$chTR    = [string][char]0x2510  # top-right corner
$chBL    = [string][char]0x2514  # bottom-left corner
$chBR    = [string][char]0x2518  # bottom-right corner
$chTDown = [string][char]0x252C  # T pointing down
$chTUp   = [string][char]0x2534  # T pointing up
$chVR    = [string][char]0x251C  # vertical + right
$chVL    = [string][char]0x2524  # vertical + left
$chCross = [string][char]0x253C  # cross
$chFull  = [string][char]0x2588  # full block
$chShade = [string][char]0x2591  # light shade

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
function Get-MaxLength {
    param([string[]]$Strings)
    $max = 0
    foreach ($s in $Strings) {
        if ($null -ne $s -and $s.Length -gt $max) { $max = $s.Length }
    }
    if ($max -lt $MaxDataLen) { return $max } else { return $MaxDataLen }
}

function Get-BarGraph {
    param([double]$Used, [double]$Total, [int]$Width = $script:CurrentLen)
    if ($Total -eq 0) { $percent = 0 } else { $percent = ($Used / $Total) * 100 }
    $numBlocks = [int][math]::Floor(($percent / 100) * $Width)
    if ($numBlocks -gt $Width) { $numBlocks = $Width }
    if ($numBlocks -lt 0)      { $numBlocks = 0 }
    return ($chFull * $numBlocks) + ($chShade * ($Width - $numBlocks))
}

# Activity bar with a right-aligned percentage (used for CPU / DISK I/O / NETWORK)
function Get-ActivityBar {
    param([int]$Percent)
    if ($Percent -lt 0)   { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }
    $width = $script:CurrentLen - 5
    return (Get-BarGraph -Used $Percent -Total 100 -Width $width) + (" {0,3}%" -f $Percent)
}

function Get-CounterValue {
    param([string]$Path)
    try {
        return (Get-Counter -Counter $Path -ErrorAction Stop).CounterSamples[0].CookedValue
    } catch {
        return 0
    }
}

# ---------------------------------------------------------------------------
# Printing (mirrors the original PRINT_* functions 1:1)
# ---------------------------------------------------------------------------
function Print-Header {
    $length = $script:CurrentLen + $MaxNameLen + $BordersAndPadding
    Write-Host ($chTL + ($chTDown * ($length - 2)) + $chTR)
    Write-Host ($chVR + ($chTUp   * ($length - 2)) + $chVL)
}

function Print-CenteredData {
    param([string]$Text)
    $maxLen     = $script:CurrentLen + $MaxNameLen - $BordersAndPadding
    $totalWidth = $maxLen + 12
    $textLen    = $Text.Length
    $padLeft    = [int][math]::Floor(($totalWidth - $textLen) / 2)
    $padRight   = $totalWidth - $textLen - $padLeft
    if ($padLeft  -lt 0) { $padLeft  = 0 }
    if ($padRight -lt 0) { $padRight = 0 }
    Write-Host ($chV + (" " * $padLeft) + $Text + (" " * $padRight) + $chV)
}

function Print-Divider {
    param([string]$Side)
    switch ($Side) {
        "top"    { $left = $chVR; $middle = $chTDown; $right = $chVL }
        "bottom" { $left = $chBL; $middle = $chTUp;   $right = $chBR }
        default  { $left = $chVR; $middle = $chCross; $right = $chVL }
    }
    $length  = $script:CurrentLen + $MaxNameLen + $BordersAndPadding
    $divider = $left
    for ($i = 0; $i -lt $length - 3; $i++) {
        $divider += $chH
        if ($i -eq 14) { $divider += $middle }
    }
    $divider += $right
    Write-Host $divider
}

function Print-Data {
    param([string]$Name, [string]$Data)

    # Pad or truncate the name column
    $nameLen = $Name.Length
    if ($nameLen -lt $MinNameLen) {
        $Name = $Name.PadRight($MinNameLen)
    } elseif ($nameLen -gt $MaxNameLen) {
        $Name = $Name.Substring(0, $MaxNameLen - 3) + "..."
    } else {
        $Name = $Name.PadRight($MaxNameLen)
    }

    # Truncate or pad the data column
    $dataLen = $Data.Length
    if ($dataLen -ge $MaxDataLen -or $dataLen -eq $MaxDataLen - 1) {
        $Data = $Data.Substring(0, $MaxDataLen - 3 - 2) + "..."
    } else {
        $Data = $Data.PadRight($script:CurrentLen)
    }

    Write-Host ($chV + " " + $Name.PadRight($MaxNameLen) + " " + $chV + " " + $Data + " " + $chV)
}

# ---------------------------------------------------------------------------
# Data collection (Windows-native sources)
# ---------------------------------------------------------------------------
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem

# Operating System Information
$os_name   = ($os.Caption -replace '^Microsoft\s+', '').Trim() + " " + $os.BuildNumber
$os_kernel = "Windows NT " + $os.Version

# Network Information
$net_current_user = "$env:USERDOMAIN\$env:USERNAME"

try {
    $net_hostname = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
} catch {
    $net_hostname = $env:COMPUTERNAME
}
if ([string]::IsNullOrWhiteSpace($net_hostname)) { $net_hostname = "Not Defined" }

# Prefer the internet-facing adapter (the one carrying the default route) so
# WSL / Hyper-V / Docker virtual switches don't shadow the real LAN address.
$primary_if = $null
try {
    $primary_if = Get-NetIPConfiguration -ErrorAction Stop |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1
} catch { }

$ipv4 = $null
if ($primary_if) { $ipv4 = ($primary_if.IPv4Address | Select-Object -First 1).IPAddress }
if (-not $ipv4) {
    $ipv4 = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1 -ExpandProperty IPAddress
}
if (-not $ipv4) {
    $ipv6 = Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '::1' -and $_.IPAddress -notlike 'fe80*' } |
        Select-Object -First 1 -ExpandProperty IPAddress
}
if     ($ipv4) { $net_machine_ip = $ipv4 }
elseif ($ipv6) { $net_machine_ip = $ipv6 }
else           { $net_machine_ip = "No IP found" }

if ($env:SSH_CLIENT) {
    $net_client_ip = ($env:SSH_CLIENT -split '\s+')[0]
} else {
    $net_client_ip = "Not connected"
}

# Scope DNS to the primary interface when known, else fall back to all of them.
if ($primary_if -and $primary_if.DNSServer) {
    $net_dns_ip = @(
        $primary_if.DNSServer |
            Where-Object { $_.AddressFamily -eq 2 } |     # 2 = IPv4
            ForEach-Object { $_.ServerAddresses } |
            Where-Object   { $_ -and $_ -notlike '127.*' } |
            Select-Object -Unique
    )
} else {
    $net_dns_ip = @()
}
if ($net_dns_ip.Count -eq 0) {
    $net_dns_ip = @(
        Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            ForEach-Object { $_.ServerAddresses } |
            Where-Object   { $_ -and $_ -notlike '127.*' } |
            Select-Object -Unique
    )
}

# CPU Information
$cpus  = @(Get-CimInstance Win32_Processor)
$cpu0  = $cpus[0]

$cpu_model = $cpu0.Name
$cpu_model = $cpu_model -replace '\((R|TM|r|tm)\)', '' -replace '\s+CPU', '' -replace '@.*$', ''
$cpu_model = ($cpu_model -replace '\s+', ' ').Trim()
if ($cpu_model.Length -gt 30) { $cpu_model = $cpu_model.Substring(0, 27) + "..." }

$cpu_sockets = $cpus.Count
$cpu_vcpus   = $cpu0.NumberOfLogicalProcessors

# Hypervisor / bare metal detection from the system model signature
$model = "$($cs.Manufacturer) $($cs.Model)"
switch -Regex ($model) {
    'VMware'                { $cpu_hypervisor = 'VMware';     break }
    'VirtualBox'            { $cpu_hypervisor = 'VirtualBox'; break }
    'Hyper-V|Virtual Machine' { $cpu_hypervisor = 'Hyper-V';  break }
    'KVM|QEMU|Bochs'        { $cpu_hypervisor = 'KVM';        break }
    'Xen'                   { $cpu_hypervisor = 'Xen';        break }
    default                 { $cpu_hypervisor = 'Bare Metal' }
}

$cpu_freq_mhz = $cpu0.MaxClockSpeed
if (-not $cpu_freq_mhz -or $cpu_freq_mhz -eq 0) { $cpu_freq_mhz = $cpu0.CurrentClockSpeed }
$cpu_freq = "{0:N2}" -f ($cpu_freq_mhz / 1000)

# Activity (CPU / DISK I/O / NETWORK), sourced live from performance counters
$cpu_activity = [int][math]::Round((Get-CounterValue '\Processor(_Total)\% Processor Time'))

$disk_activity = [int][math]::Round((Get-CounterValue '\PhysicalDisk(_Total)\% Disk Time'))
if ($disk_activity -gt 100) { $disk_activity = 100 }

$net_activity = 0
try {
    $netBytes = (Get-Counter '\Network Interface(*)\Bytes Total/sec' -ErrorAction Stop).CounterSamples
    $netBw    = (Get-Counter '\Network Interface(*)\Current Bandwidth' -ErrorAction Stop).CounterSamples
    $bwMap = @{}
    foreach ($s in $netBw) { $bwMap[$s.InstanceName] = $s.CookedValue }
    foreach ($s in $netBytes) {
        if ($s.InstanceName -match 'loopback|isatap|teredo') { continue }
        $bw = $bwMap[$s.InstanceName]
        if ($bw -gt 0) {
            $u = ($s.CookedValue * 8 / $bw) * 100
            if ($u -gt $net_activity) { $net_activity = $u }
        }
    }
} catch {
    $net_activity = 0
}
$net_activity = [int][math]::Round([math]::Min($net_activity, 100))

# Memory Information (KiB from CIM -> GiB)
$mem_total   = [double]$os.TotalVisibleMemorySize
$mem_avail   = [double]$os.FreePhysicalMemory
$mem_used    = $mem_total - $mem_avail
$mem_percent = "{0:N2}" -f ($mem_used / $mem_total * 100)
$mem_total_gb = "{0:N2}" -f ($mem_total / 1024 / 1024)
$mem_used_gb  = "{0:N2}" -f ($mem_used  / 1024 / 1024)

# Disk Information (the configured volume)
$vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$VolumeDrive'"
$root_total    = [double]$vol.Size
$root_free     = [double]$vol.FreeSpace
$root_used     = $root_total - $root_free
$root_total_gb = "{0:N2}" -f ($root_total / 1GB)
$root_used_gb  = "{0:N2}" -f ($root_used  / 1GB)
$disk_percent  = "{0:N2}" -f ($root_used / $root_total * 100)

# Last login and uptime
$last_login_time = "N/A"
try {
    $session = Get-CimInstance Win32_LogonSession -ErrorAction Stop |
        Where-Object { $_.LogonType -in 2, 10, 11 } |
        Sort-Object -Property StartTime -Descending |
        Select-Object -First 1
    if ($session -and $session.StartTime) {
        $last_login_time = ([datetime]$session.StartTime).ToString("MMM dd HH:mm yyyy")
    }
} catch { }
if ($last_login_time -eq "N/A") {
    try {
        $lu = (Get-LocalUser -Name $env:USERNAME -ErrorAction Stop).LastLogon
        if ($lu) { $last_login_time = $lu.ToString("MMM dd HH:mm yyyy") } else { $last_login_time = "Never logged in" }
    } catch { }
}

$uptime      = (Get-Date) - $os.LastBootUpTime
$sys_uptime  = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

# Cores label
$cpu_cores_line = "$cpu_vcpus vCPU(s) / $cpu_sockets Socket(s)"

# ---------------------------------------------------------------------------
# Set current length before graphs get calculated (same set as the original)
# ---------------------------------------------------------------------------
$script:CurrentLen = Get-MaxLength @(
    $ReportTitle
    $os_name
    $os_kernel
    $net_hostname
    $net_machine_ip
    $net_client_ip
    $net_current_user
    $cpu_model
    $cpu_cores_line
    $cpu_hypervisor
    "$cpu_freq GHz"
    "$root_used_gb/$root_total_gb GB [$disk_percent%]"
    "$mem_used_gb/$mem_total_gb GiB [$mem_percent%]"
    $last_login_time
    $sys_uptime
)

# Create graphs
$cpu_bar     = Get-ActivityBar $cpu_activity
$disk_io_bar = Get-ActivityBar $disk_activity
$net_bar     = Get-ActivityBar $net_activity
$mem_bar     = Get-BarGraph $mem_used  $mem_total
$disk_bar    = Get-BarGraph $root_used $root_total

# ---------------------------------------------------------------------------
# Machine Report
# ---------------------------------------------------------------------------
Print-Header
Print-CenteredData $ReportTitle
Print-CenteredData "TR-100 MACHINE REPORT"
Print-Divider "top"
Print-Data "OS"     $os_name
Print-Data "KERNEL" $os_kernel
Print-Divider
Print-Data "HOSTNAME"   $net_hostname
Print-Data "MACHINE IP" $net_machine_ip
Print-Data "CLIENT  IP" $net_client_ip

for ($i = 0; $i -lt $net_dns_ip.Count; $i++) {
    Print-Data ("DNS  IP " + ($i + 1)) $net_dns_ip[$i]
}

Print-Data "USER" $net_current_user
Print-Divider
Print-Data "PROCESSOR"  $cpu_model
Print-Data "CORES"      $cpu_cores_line
Print-Data "HYPERVISOR" $cpu_hypervisor
Print-Data "CPU FREQ"   "$cpu_freq GHz"
Print-Data "CPU"        $cpu_bar
Print-Data "DISK I/O"   $disk_io_bar
Print-Data "NETWORK"    $net_bar
Print-Divider
Print-Data "VOLUME"     "$root_used_gb/$root_total_gb GB [$disk_percent%]"
Print-Data "DISK USAGE" $disk_bar
Print-Divider
Print-Data "MEMORY" "$mem_used_gb/$mem_total_gb GiB [$mem_percent%]"
Print-Data "USAGE"  $mem_bar
Print-Divider
Print-Data "LAST LOGIN" $last_login_time
Print-Data "UPTIME"     $sys_uptime
Print-Divider "bottom"
