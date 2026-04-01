$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'CampusWifi.Core.psm1') -Force

try {
    $saved = Get-CampusWifiSavedState
    $credentials = Get-CampusWifiRuntimeCredential -Config $saved.Config -AllowStored
    if (-not $credentials) {
        Write-CampusWifiLog -Message 'No saved credential is available for command-line login.'
        exit 1
    }

    $state = Get-CampusWifiState -Config $saved.Config
    if ($state.State -ne 'CampusWifiNeedsAuth') {
        Write-CampusWifiLog -Message "Command-line login skipped: $($state.Reason)"
        exit 0
    }

    $result = Invoke-CampusWifiLogin -Config $saved.Config -Credentials $credentials
    if (-not $result.Success) {
        exit 1
    }
} catch {
    Write-CampusWifiLog -Message "Unhandled error: $($_.Exception.Message)"
    throw
}
