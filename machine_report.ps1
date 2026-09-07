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

# Sum of every process's CPU time (100ns ticks). Sampled twice around a short
# window to derive CPU% without WMI or performance counters.
function Get-CpuTicks {
    $sum = 0
    foreach ($proc in [System.Diagnostics.Process]::GetProcesses()) {
        try { $sum += $proc.TotalProcessorTime.Ticks } catch { }
        $proc.Dispose()
    }
    return $sum
}

# ---------------------------------------------------------------------------
# Data collection (registry / .NET only - no WMI/CIM, which is slow to warm up)
# ---------------------------------------------------------------------------
Add-Type -AssemblyName Microsoft.VisualBasic

# Operating System Information (from the registry)
$os_reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
    -Name CurrentBuildNumber, EditionID, CurrentMajorVersionNumber, CurrentMinorVersionNumber `
    -ErrorAction SilentlyContinue
$os_build   = [int]$os_reg.CurrentBuildNumber
$os_product = if ($os_build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
$os_name    = "$os_product $($os_reg.EditionID) $os_build"
$os_kernel  = "Windows NT $($os_reg.CurrentMajorVersionNumber).$($os_reg.CurrentMinorVersionNumber).$os_build"

# Network Information
$net_current_user = "$env:USERDOMAIN\$env:USERNAME"

try {
    $net_hostname = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
} catch {
    $net_hostname = $env:COMPUTERNAME
}
if ([string]::IsNullOrWhiteSpace($net_hostname)) { $net_hostname = "Not Defined" }

# Machine IP + DNS via .NET (milliseconds), preferring the internet-facing
# adapter (the one carrying an IPv4 gateway) so WSL / Hyper-V / Docker virtual
# switches don't shadow the real LAN address. Avoids the very slow
# Get-NetIPConfiguration cmdlet.
$net_machine_ip = "No IP found"
$net_dns_ip     = @()
try {
    $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object {
            $_.OperationalStatus -eq 'Up' -and
            $_.NetworkInterfaceType -ne 'Loopback' -and
            $_.NetworkInterfaceType -ne 'Tunnel'
        }

    $primary = $null
    foreach ($n in $nics) {
        $gw = $n.GetIPProperties().GatewayAddresses |
            Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0' }
        if ($gw) { $primary = $n; break }
    }
    if (-not $primary) { $primary = $nics | Select-Object -First 1 }

    if ($primary) {
        $props = $primary.GetIPProperties()
        $ip = $props.UnicastAddresses |
            Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -notlike '169.254.*' } |
            Select-Object -First 1
        if ($ip) {
            $net_machine_ip = $ip.Address.ToString()
        } else {
            $ip6 = $props.UnicastAddresses |
                Where-Object { $_.Address.AddressFamily -eq 'InterNetworkV6' -and -not $_.Address.IsIPv6LinkLocal } |
                Select-Object -First 1
            if ($ip6) { $net_machine_ip = $ip6.Address.ToString() }
        }
        $net_dns_ip = @(
            $props.DnsAddresses |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notlike '127.*' } |
                ForEach-Object { $_.ToString() } |
                Select-Object -Unique
        )
    }
} catch { }

if ($env:SSH_CLIENT) {
    $net_client_ip = ($env:SSH_CLIENT -split '\s+')[0]
} else {
    $net_client_ip = "Not connected"
}

# --- Activity sample, snapshot 1 (t0). The static collection below doubles as
# the sampling window, so CPU% / NETWORK% add almost no extra wall-clock. ---
$act_cpu0 = Get-CpuTicks
$act_net0 = 0.0
if ($primary) { $s0 = $primary.GetIPStatistics(); $act_net0 = [double]$s0.BytesReceived + [double]$s0.BytesSent }
$act_q0 = [System.Diagnostics.Stopwatch]::GetTimestamp()

# CPU Information (model + frequency from the registry, logical count from .NET)
$cpu_reg_key  = 'HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
$cpu_model    = [string][Microsoft.Win32.Registry]::GetValue($cpu_reg_key, 'ProcessorNameString', '')
$cpu_freq_mhz = [double][Microsoft.Win32.Registry]::GetValue($cpu_reg_key, '~MHz', 0)

$cpu_model = $cpu_model -replace '\((R|TM|r|tm)\)', '' -replace '\s+CPU', '' -replace '@.*$', ''
$cpu_model = ($cpu_model -replace '\s+', ' ').Trim()
if ($cpu_model.Length -gt 30) { $cpu_model = $cpu_model.Substring(0, 27) + "..." }

$cpu_vcpus   = [Environment]::ProcessorCount
$cpu_sockets = 1   # workstation assumption; edit for a multi-socket server
$cpu_freq    = "{0:N2}" -f ($cpu_freq_mhz / 1000)

# Hypervisor / bare metal detection from the BIOS system model signature
$bios_reg = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' `
    -Name SystemManufacturer, SystemProductName -ErrorAction SilentlyContinue
$model = "$($bios_reg.SystemManufacturer) $($bios_reg.SystemProductName)"
switch -Regex ($model) {
    'VMware'                  { $cpu_hypervisor = 'VMware';     break }
    'VirtualBox'              { $cpu_hypervisor = 'VirtualBox'; break }
    'Hyper-V|Virtual Machine' { $cpu_hypervisor = 'Hyper-V';   break }
    'KVM|QEMU|Bochs'          { $cpu_hypervisor = 'KVM';        break }
    'Xen'                     { $cpu_hypervisor = 'Xen';        break }
    default                   { $cpu_hypervisor = 'Bare Metal' }
}

# Memory Information (Microsoft.VisualBasic ComputerInfo -> bytes, no WMI)
$comp_info    = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
$mem_total    = [double]$comp_info.TotalPhysicalMemory
$mem_avail    = [double]$comp_info.AvailablePhysicalMemory
$mem_used     = $mem_total - $mem_avail
$mem_percent  = "{0:N2}" -f ($mem_used / $mem_total * 100)
$mem_total_gb = "{0:N2}" -f ($mem_total / 1GB)
$mem_used_gb  = "{0:N2}" -f ($mem_used  / 1GB)

# Disk Information (the configured volume) via .NET DriveInfo (instant, no WMI)
$drive         = [System.IO.DriveInfo]::new($VolumeDrive)
$root_total    = [double]$drive.TotalSize
$root_free     = [double]$drive.TotalFreeSpace
$root_used     = $root_total - $root_free
$root_total_gb = "{0:N2}" -f ($root_total / 1GB)
$root_used_gb  = "{0:N2}" -f ($root_used  / 1GB)
$disk_percent  = "{0:N2}" -f ($root_used / $root_total * 100)

# Uptime from the system tick count (instant, no WMI). TickCount64 exists on
# PowerShell 7; on Windows PowerShell 5.1 (.NET Framework) it is absent, so fall
# back to the 32-bit tick read as unsigned (accurate up to ~49.7 days).
try { $uptime_ms = [double][Environment]::TickCount64 } catch { $uptime_ms = 0 }
if (-not $uptime_ms) {
    $uptime_ms = [double][BitConverter]::ToUInt32([BitConverter]::GetBytes([Environment]::TickCount), 0)
}
$uptime     = [TimeSpan]::FromMilliseconds($uptime_ms)
$sys_uptime = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

# Last login via quser (WMI-free); best-effort, falls back to N/A
$last_login_time = "N/A"
try {
    $quser_lines = quser 2>$null
    if ($quser_lines) {
        foreach ($line in $quser_lines) {
            if ($line -match "^\s*>?\s*$([regex]::Escape($env:USERNAME))\b") {
                $m = [regex]::Match($line, '\d{1,2}[/.]\d{1,2}[/.]\d{2,4}\s+\d{1,2}:\d{2}(:\d{2})?(\s*[AP]M)?')
                if ($m.Success) { $last_login_time = $m.Value.Trim() }
                break
            }
        }
    }
} catch { }

# --- Activity sample, snapshot 2 (t1). Guarantee at least a 150ms window. ---
$act_elapsed_ms = ([System.Diagnostics.Stopwatch]::GetTimestamp() - $act_q0) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
if ($act_elapsed_ms -lt 150) { Start-Sleep -Milliseconds ([int](150 - $act_elapsed_ms)) }
$act_cpu1 = Get-CpuTicks
$act_net1 = 0.0
if ($primary) { $s1 = $primary.GetIPStatistics(); $act_net1 = [double]$s1.BytesReceived + [double]$s1.BytesSent }
$act_sec  = ([System.Diagnostics.Stopwatch]::GetTimestamp() - $act_q0) / [System.Diagnostics.Stopwatch]::Frequency

$cpu_activity = 0
if ($act_sec -gt 0) {
    $cpu_activity = [int][math]::Round((($act_cpu1 - $act_cpu0) / ([System.TimeSpan]::TicksPerSecond * $act_sec * [Environment]::ProcessorCount)) * 100)
}
if ($cpu_activity -lt 0)   { $cpu_activity = 0 }
if ($cpu_activity -gt 100) { $cpu_activity = 100 }

$net_activity = 0
if ($primary -and $primary.Speed -gt 0 -and $act_sec -gt 0) {
    $net_bps = (($act_net1 - $act_net0) * 8) / $act_sec
    $net_activity = [int][math]::Round(($net_bps / $primary.Speed) * 100)
}
if ($net_activity -lt 0)   { $net_activity = 0 }
if ($net_activity -gt 100) { $net_activity = 100 }

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
$cpu_bar  = Get-ActivityBar $cpu_activity
$net_bar  = Get-ActivityBar $net_activity
$mem_bar  = Get-BarGraph $mem_used  $mem_total
$disk_bar = Get-BarGraph $root_used $root_total

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
