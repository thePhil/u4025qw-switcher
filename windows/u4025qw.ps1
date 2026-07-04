#!/usr/bin/env pwsh
<#
.SYNOPSIS
  u4025qw (Windows) — switch input source on a Dell U4025QW via DDC/CI.

.DESCRIPTION
  Uses the Windows Monitor Configuration API (dxva2.dll, built into Windows)
  through in-memory P/Invoke — no external binaries, no admin rights.

  Commands:
    u4025qw.ps1 <input|alias>   switch input (dp, hdmi, usbc, tb, linux, work, mac)
    u4025qw.ps1 status          show the currently active input
    u4025qw.ps1 toggle          toggle between $ToggleA and $ToggleB

  Note: needs FullLanguage mode (check: $ExecutionContext.SessionState.LanguageMode).
  Add-Type is blocked under Constrained Language Mode / strict WDAC policies.
#>
param([Parameter(Position = 0)][string]$Command = 'help')

$ErrorActionPreference = 'Stop'

# VCP 0x60 values, verified against the monitor's capabilities report (2026-07-05):
# 0x0f DisplayPort, 0x11 HDMI, 0x19 Thunderbolt/USB-C
$Inputs = [ordered]@{ dp = 0x0f; hdmi = 0x11; usbc = 0x19 }
$Aliases = @{ tb = 'usbc'; linux = 'dp'; work = 'usbc'; mac = 'usbc' }
$ToggleA = 'dp'
$ToggleB = 'usbc'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Ddc {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PHYSICAL_MONITOR {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr rect, IntPtr data);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc proc, IntPtr data);
    [DllImport("dxva2.dll")]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint count);
    [DllImport("dxva2.dll")]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count,
        [Out] PHYSICAL_MONITOR[] monitors);
    [DllImport("dxva2.dll")]
    public static extern bool SetVCPFeature(IntPtr hMonitor, byte code, uint value);
    [DllImport("dxva2.dll")]
    public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr hMonitor, byte code,
        IntPtr pvct, out uint current, out uint max);
    [DllImport("dxva2.dll")]
    public static extern bool DestroyPhysicalMonitor(IntPtr hMonitor);

    public static List<PHYSICAL_MONITOR> GetPhysicalMonitors() {
        var result = new List<PHYSICAL_MONITOR>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr hMon, IntPtr hdc, IntPtr rect, IntPtr data) {
            uint count;
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, out count) && count > 0) {
                var mons = new PHYSICAL_MONITOR[count];
                if (GetPhysicalMonitorsFromHMONITOR(hMon, count, mons)) result.AddRange(mons);
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@

function Get-InputName([uint32]$Value) {
    foreach ($kv in $Inputs.GetEnumerator()) { if ($kv.Value -eq $Value) { return $kv.Key } }
    return 'unknown'
}

# Runs $Action on every monitor that answers a DDC read of VCP 0x60
# (the laptop's internal panel doesn't, so this targets the Dell).
function Invoke-OnDdcMonitor([scriptblock]$Action) {
    $monitors = [Ddc]::GetPhysicalMonitors()
    if (-not $monitors) { throw 'no monitors found' }
    $hit = $false
    try {
        foreach ($mon in $monitors) {
            $cur = [uint32]0; $max = [uint32]0
            if ([Ddc]::GetVCPFeatureAndVCPFeatureReply($mon.hPhysicalMonitor, 0x60, [IntPtr]::Zero,
                    [ref]$cur, [ref]$max)) {
                $hit = $true
                & $Action $mon.hPhysicalMonitor $cur
            }
        }
    } finally {
        foreach ($mon in $monitors) { [void][Ddc]::DestroyPhysicalMonitor($mon.hPhysicalMonitor) }
    }
    if (-not $hit) { throw 'no DDC/CI-capable monitor responded (external display connected and awake?)' }
}

function Set-MonitorInput([string]$Name) {
    $value = $Inputs[$Name]
    Write-Host ("switching to {0} (0x{1:x2})" -f $Name, $value)
    Invoke-OnDdcMonitor {
        param($handle, $current)
        if (-not [Ddc]::SetVCPFeature($handle, 0x60, $value)) { throw 'SetVCPFeature failed' }
    }
}

switch ($Command) {
    'status' {
        Invoke-OnDdcMonitor {
            param($handle, $current)
            Write-Host ("active input: {0} (0x{1:x2})" -f (Get-InputName $current), $current)
        }
    }
    'toggle' {
        $target = $ToggleA
        Invoke-OnDdcMonitor {
            param($handle, $current)
            if ($current -eq $Inputs[$ToggleA]) { $script:target = $ToggleB }
        }
        Set-MonitorInput $target
    }
    'help' {
        Write-Host @"
u4025qw.ps1 — switch input source on a Dell U4025QW via DDC/CI.

Usage:
  u4025qw.ps1 <input|alias>   switch input ($($Inputs.Keys -join ', ') | $($Aliases.Keys -join ', '))
  u4025qw.ps1 status          show the currently active input
  u4025qw.ps1 toggle          toggle between $ToggleA and $ToggleB
"@
        exit 1
    }
    default {
        $name = if ($Aliases.Contains($Command)) { $Aliases[$Command] } else { $Command }
        if (-not $Inputs.Contains($name)) {
            Write-Error ("unknown input '{0}' (know: {1} {2})" -f $Command,
                ($Inputs.Keys -join ' '), ($Aliases.Keys -join ' '))
            exit 1
        }
        Set-MonitorInput $name
    }
}
