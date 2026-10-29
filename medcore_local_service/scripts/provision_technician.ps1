# PowerShell Commissioning Helper for Field Technicians
param (
    [ValidateSet("status", "generate", "set", "help")]
    [string]$Action = "status",
    [string]$Secret = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$serviceDir = Split-Path -Parent $scriptDir

Push-Location $serviceDir
try {
    if ($Action -eq "set") {
        if (-not $Secret -or $Secret.Length -lt 12) {
            Write-Error "Action 'set' requires -Secret parameter with at least 12 characters."
            exit 1
        }
        dart run bin/commission.dart set "$Secret"
    } elseif ($Action -eq "generate") {
        dart run bin/commission.dart generate
    } elseif ($Action -eq "status") {
        dart run bin/commission.dart status
    } else {
        dart run bin/commission.dart help
    }
} finally {
    Pop-Location
}
