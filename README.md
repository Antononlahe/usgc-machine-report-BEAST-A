NOT MAINTAINED ON PURPOSE. DIG INTO THE SCRIPT AND ADAPT IT FOR YOUR OWN USE CASE. CUSTOMIZE IT TO YOUR HEARTS CONTENT.

# TR-100 Machine Report (Windows / PowerShell)
SKU: TR-100, filed under Technical Reports (TR).

What is it?
A machine information report used at [United States Graphics Company](https://x.com/usgraphics).

"Machine Report" is similar to Neofetch, but very basic. This is a **native Windows PowerShell port** of the original bash script: it displays useful machine information right in the terminal session. Reference it from your PowerShell profile and it prints when you open a new shell (or log into the box over SSH). See installation instructions below.

This fork is Windows-only. The original bash script has been dropped; everything lives in `machine_report.ps1`.

## What differs from the original bash version

- **Native Windows data sources, no WMI.** OS/kernel, CPU, memory, disk, uptime and hostname come from the registry and .NET (`Microsoft.VisualBasic.Devices.ComputerInfo`, `DriveInfo`, `NetworkInterface`), not `/proc`, `lscpu`, `zfs`. WMI/CIM is avoided on purpose - a single CIM call pays ~0.5s of provider warmup - so the report renders in roughly 1.3s instead of ~3s.
- **Activity monitor replaces Unix load average.** Windows keeps no 1/5/15-minute load history, so the `LOAD` section is replaced by two live bars sampled over a short (~150ms) window: `CPU` (% busy across all logical processors) and `NETWORK` (link utilization of the primary adapter). Live disk I/O was intentionally dropped - it has no fast non-WMI source - but disk *capacity* is still shown below.
- **ZFS section removed.** There is no ZFS on Windows; the report shows the configured volume (default `C:`).

# Software Philosophy
Since it is a script, you've got the source code. Just modify that for your needs. No modules, no DSL, no config files, none of it. Single file for easy deployment. The only abstraction that's acceptable is variables at the top of the script to customize the system, and it stays minimal (`$ReportTitle`, `$VolumeDrive`).

Problem with providing tools with a silver spoon is that you kill the creativity of the users. Remember MySpace? Let people customize the hell out of it and share it. Central theme:

```
ENCOURAGE USERS TO DIRECTLY EDIT THE SOURCE
```

The "Machine Report" section at the end of the script prints the output with a straight run of `Print-Data` calls - a near 1:1 mapping to what appears on screen, so it's easy to read and reorder.

# Design Philosophy
Tabular, short, clear and concise. The tool's job is to inform the user of the current state of the system they are operating. No emojis, no colors (default).

# Assumed Setup
This port targets a normal Windows workstation or server:

- Windows 10/11 or Windows Server
- Windows PowerShell 5.1 or PowerShell 7+
- A UTF-8 capable terminal (Windows Terminal recommended) for the box-drawing and bar glyphs

If your system is different, look up the offending line and adapt it.

# Dependencies
- Windows PowerShell 5.1 or PowerShell 7+. Everything is built in - registry access, .NET types, and `quser` for last login.

Notes:
- `LAST LOGIN` is read from `quser` and parsed best-effort; if the output can't be parsed it shows `N/A`. `quser` ships with Pro/Enterprise/Server editions.
- `UPTIME` uses `TickCount64` on PowerShell 7; on 5.1 it falls back to the 32-bit tick counter, which is accurate up to ~49.7 days of uptime.
- `CORES` assumes a single socket (the common workstation case). Edit `$cpu_sockets` for a multi-socket server.

# Installation

Copy `machine_report.ps1` to a stable location, e.g. `~\machine_report.ps1` (`$HOME\machine_report.ps1`).

Reference it from your PowerShell profile so it runs on each interactive session. Open your profile with `notepad $PROFILE` (create it if prompted) and add:

```powershell
# Run Machine Report only in an interactive console session
if ($Host.Name -eq 'ConsoleHost') {
    & "$HOME\machine_report.ps1"
}
```

If scripts are blocked by execution policy, allow local scripts for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

For login sessions over SSH to a Windows host, the same profile line applies when the SSH default shell is PowerShell; `CLIENT IP` is read from `$env:SSH_CLIENT`.

# License
BSD 3 Clause License, Copyright (c) 2024, U.S. Graphics, LLC. See [`LICENSE`](LICENSE) file for license information.
