$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'CampusWifi.Core.psm1') -Force
Set-CampusWifiStartupEnabled -Enabled $true
Write-Host "开机自启入口已写入: $((Get-CampusWifiPaths).StartupLauncherPath)"
