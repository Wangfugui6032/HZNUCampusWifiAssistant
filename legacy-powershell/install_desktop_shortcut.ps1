$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'CampusWifi.Core.psm1') -Force
Install-CampusWifiDesktopShortcut
Write-Host "桌面快捷方式已创建: $((Get-CampusWifiPaths).DesktopShortcutPath)"
