$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not ('SrunCodec' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Text;

public static class SrunCodec
{
    private static uint[] SEncode(string text, bool includeLength)
    {
        int size = (text.Length + 3) / 4;
        uint[] result = includeLength ? new uint[size + 1] : new uint[size];
        for (int i = 0; i < text.Length; i++)
        {
            result[i >> 2] |= (uint)(byte)text[i] << ((i & 3) * 8);
        }
        if (includeLength)
        {
            result[size] = (uint)text.Length;
        }
        return result;
    }

    public static string XEncode(string message, string key)
    {
        if (string.IsNullOrEmpty(message))
        {
            return string.Empty;
        }

        uint[] v = SEncode(message, true);
        uint[] k = SEncode(key, false);
        if (k.Length < 4)
        {
            Array.Resize(ref k, 4);
        }

        int n = v.Length - 1;
        uint z = v[n], y = v[0], c = 0x9E3779B9, d = 0;
        int q = 6 + 52 / (n + 1);

        while (q-- > 0)
        {
            d += c;
            uint e = (d >> 2) & 3;
            for (int p = 0; p < n; p++)
            {
                y = v[p + 1];
                uint m = ((z >> 5) ^ (y << 2)) + (((y >> 3) ^ (z << 4)) ^ (d ^ y));
                m += k[(p & 3) ^ e] ^ z;
                z = v[p] += m;
            }

            y = v[0];
            uint mLast = ((z >> 5) ^ (y << 2)) + (((y >> 3) ^ (z << 4)) ^ (d ^ y));
            mLast += k[(n & 3) ^ e] ^ z;
            z = v[n] += mLast;
        }

        byte[] bytes = new byte[v.Length * 4];
        for (int i = 0; i < v.Length; i++)
        {
            bytes[i * 4] = (byte)(v[i] & 0xFF);
            bytes[i * 4 + 1] = (byte)((v[i] >> 8) & 0xFF);
            bytes[i * 4 + 2] = (byte)((v[i] >> 16) & 0xFF);
            bytes[i * 4 + 3] = (byte)((v[i] >> 24) & 0xFF);
        }

        return Encoding.GetEncoding("ISO-8859-1").GetString(bytes);
    }
}
"@
}

function Get-CampusWifiPaths {
    $scriptDir = $PSScriptRoot
    [pscustomobject]@{
        ScriptDir            = $scriptDir
        ConfigPath           = Join-Path $scriptDir 'config.json'
        ExampleConfigPath    = Join-Path $scriptDir 'config.example.json'
        CredentialPath       = Join-Path $scriptDir 'credential.xml'
        LogPath              = Join-Path $scriptDir 'campus_wifi_login.log'
        AppScriptPath        = Join-Path $scriptDir 'CampusWifiApp.ps1'
        VbsLauncherPath      = Join-Path $scriptDir 'CampusWifiLauncher.vbs'
        DesktopShortcutPath  = Join-Path ([Environment]::GetFolderPath('Desktop')) 'CampusWifiApp.lnk'
        StartupLauncherPath  = Join-Path ([Environment]::GetFolderPath('Startup')) 'CampusWifiLogin.vbs'
        LegacyStartupCmdPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'CampusWifiLogin.cmd'
    }
}

function Write-CampusWifiLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$LogPath = (Get-CampusWifiPaths).LogPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogPath -Value "[$timestamp] $Message"
}

function Invoke-CampusWifiStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [scriptblock]$StatusCallback,
        [string]$LogPath = (Get-CampusWifiPaths).LogPath
    )

    Write-CampusWifiLog -Message $Message -LogPath $LogPath
    if ($StatusCallback) {
        & $StatusCallback $Message
    }
}

function Get-CampusWifiConfig {
    param([string]$ConfigPath = (Get-CampusWifiPaths).ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $examplePath = (Get-CampusWifiPaths).ExampleConfigPath
        if (Test-Path -LiteralPath $examplePath) {
            Copy-Item -LiteralPath $examplePath -Destination $ConfigPath -Force
        } else {
            throw "Config file not found: $ConfigPath"
        }
    }

    Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

function Save-CampusWifiConfig {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [string]$ConfigPath = (Get-CampusWifiPaths).ConfigPath
    )

    $json = $Config | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
}

function Get-CampusWifiSavedState {
    param([string]$ConfigPath = (Get-CampusWifiPaths).ConfigPath)

    $paths = Get-CampusWifiPaths
    $config = Get-CampusWifiConfig -ConfigPath $ConfigPath

    $rememberCredentials = $false
    if ($config.PSObject.Properties['rememberCredentials']) {
        $rememberCredentials = [bool]$config.rememberCredentials
    } elseif (Test-Path -LiteralPath $paths.CredentialPath) {
        $rememberCredentials = $true
    }

    $autoStart = $false
    if ($config.PSObject.Properties['autoStart']) {
        $autoStart = [bool]$config.autoStart
    } elseif (Test-Path -LiteralPath $paths.StartupLauncherPath) {
        $autoStart = $true
    }

    $studentId = ''
    if (Test-Path -LiteralPath $paths.CredentialPath) {
        try {
            $credential = Import-Clixml -LiteralPath $paths.CredentialPath
            $studentId = [string]$credential.UserName
        } catch {
            $studentId = ''
        }
    } elseif ($config.credentials -and $config.credentials.studentId) {
        $studentId = [string]$config.credentials.studentId
    }

    [pscustomobject]@{
        Config              = $config
        StudentId           = $studentId
        RememberCredentials = $rememberCredentials
        AutoStart           = $autoStart
    }
}

function Save-CampusWifiCredential {
    param(
        [Parameter(Mandatory = $true)][string]$StudentId,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$CredentialPath = (Get-CampusWifiPaths).CredentialPath
    )

    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($StudentId, $securePassword)
    $credential | Export-Clixml -LiteralPath $CredentialPath
}

function Remove-CampusWifiCredential {
    param([string]$CredentialPath = (Get-CampusWifiPaths).CredentialPath)

    if (Test-Path -LiteralPath $CredentialPath) {
        Remove-Item -LiteralPath $CredentialPath -Force
    }
}

function Get-CampusWifiLauncherVbsContent {
    param([string]$Arguments = '')

    $paths = Get-CampusWifiPaths
    $escapedScript = $paths.AppScriptPath.Replace('"', '""')
    $escapedArgs = $Arguments.Trim()
    if ($escapedArgs) {
        return 'Set shell = CreateObject("WScript.Shell")' + "`r`n" + 'shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $escapedScript + '"" ' + $escapedArgs + '", 0'
    }

    'Set shell = CreateObject("WScript.Shell")' + "`r`n" + 'shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $escapedScript + '""", 0'
}

function Write-CampusWifiLauncherScript {
    $paths = Get-CampusWifiPaths
    $content = Get-CampusWifiLauncherVbsContent
    Set-Content -LiteralPath $paths.VbsLauncherPath -Value $content -Encoding ASCII
}

function Set-CampusWifiStartupEnabled {
    param([Parameter(Mandatory = $true)][bool]$Enabled)

    $paths = Get-CampusWifiPaths
    Write-CampusWifiLauncherScript

    if (Test-Path -LiteralPath $paths.LegacyStartupCmdPath) {
        Remove-Item -LiteralPath $paths.LegacyStartupCmdPath -Force
    }

    if ($Enabled) {
        $content = Get-CampusWifiLauncherVbsContent -Arguments '-AutoStart'
        Set-Content -LiteralPath $paths.StartupLauncherPath -Value $content -Encoding ASCII
    } elseif (Test-Path -LiteralPath $paths.StartupLauncherPath) {
        Remove-Item -LiteralPath $paths.StartupLauncherPath -Force
    }
}

function Install-CampusWifiDesktopShortcut {
    $paths = Get-CampusWifiPaths
    Write-CampusWifiLauncherScript
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($paths.DesktopShortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\wscript.exe"
    $shortcut.Arguments = "`"$($paths.VbsLauncherPath)`""
    $shortcut.WorkingDirectory = $paths.ScriptDir
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
    $shortcut.Save()
}

function Save-CampusWifiAppSettings {
    param(
        [Parameter(Mandatory = $true)][string]$StudentId,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][bool]$RememberCredentials,
        [Parameter(Mandatory = $true)][bool]$AutoStart
    )

    $paths = Get-CampusWifiPaths
    $config = Get-CampusWifiConfig -ConfigPath $paths.ConfigPath
    $config.rememberCredentials = $RememberCredentials
    $config.autoStart = $AutoStart

    if (-not $config.credentials) {
        $config | Add-Member -MemberType NoteProperty -Name credentials -Value ([pscustomobject]@{ studentId = ''; password = '' })
    }

    $config.credentials.studentId = $StudentId
    $config.credentials.password = if ($RememberCredentials) { 'stored_in_credential_file' } else { '' }

    Save-CampusWifiConfig -Config $config -ConfigPath $paths.ConfigPath

    if ($RememberCredentials) {
        Save-CampusWifiCredential -StudentId $StudentId -Password $Password -CredentialPath $paths.CredentialPath
    } else {
        Remove-CampusWifiCredential -CredentialPath $paths.CredentialPath
    }

    Set-CampusWifiStartupEnabled -Enabled $AutoStart
    Install-CampusWifiDesktopShortcut
}

function Get-CampusWifiRuntimeCredential {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [string]$StudentId,
        [string]$Password,
        [switch]$AllowStored
    )

    $paths = Get-CampusWifiPaths
    if ($StudentId -and $Password) {
        return [pscustomobject]@{ StudentId = $StudentId; Password = $Password }
    }

    if ($AllowStored -and (Test-Path -LiteralPath $paths.CredentialPath)) {
        $stored = Import-Clixml -LiteralPath $paths.CredentialPath
        return [pscustomobject]@{
            StudentId = [string]$stored.UserName
            Password  = $stored.GetNetworkCredential().Password
        }
    }

    if ($Config.credentials -and $Config.credentials.studentId -and $Config.credentials.password) {
        return [pscustomobject]@{
            StudentId = [string]$Config.credentials.studentId
            Password  = [string]$Config.credentials.password
        }
    }

    return $null
}

function Get-WifiInterfaceSnapshot {
    $output = @(netsh wlan show interfaces 2>$null)
    $text = $output -join "`n"

    if ($text -match 'There is no wireless interface on the system') {
        return [pscustomobject]@{
            Exists      = $false
            Name        = $null
            State       = ''
            CurrentSsid = $null
            Text        = $text
        }
    }

    $nameLine = $output | Where-Object {
        $_ -match '^\s*Name\s*:\s*(.+)$'
    } | Select-Object -First 1

    $stateLine = $output | Where-Object {
        $_ -match '^\s*State\s*:\s*(.+)$'
    } | Select-Object -First 1

    $ssidLine = $output | Where-Object {
        $_ -match '^\s*SSID\s*:\s*(.+)$' -and $_ -notmatch 'BSSID'
    } | Select-Object -First 1

    $name = if ($nameLine) {
        ($nameLine -replace '^\s*Name\s*:\s*', '').Trim()
    } else {
        'WLAN'
    }

    $state = if ($stateLine) {
        ($stateLine -replace '^\s*State\s*:\s*', '').Trim()
    } else {
        ''
    }

    $ssid = if ($ssidLine) {
        ($ssidLine -replace '^\s*SSID\s*:\s*', '').Trim()
    } else {
        $null
    }

    [pscustomobject]@{
        Exists      = $true
        Name        = $name
        State       = $state
        CurrentSsid = $ssid
        Text        = $text
    }
}

function Get-WifiStatus {
    $driversOutput = @(netsh wlan show drivers 2>$null)
    $driversText = $driversOutput -join "`n"
    if ($driversText -match 'There is no wireless interface on the system') {
        return [pscustomobject]@{ Exists = $false; Enabled = $false; Name = $null; State = $null; CurrentSsid = $null }
    }

    $snapshot = Get-WifiInterfaceSnapshot
    if (-not $snapshot.Exists) {
        return [pscustomobject]@{ Exists = $false; Enabled = $false; Name = $null; State = $null; CurrentSsid = $null }
    }

    $enabled = $true
    if ($snapshot.Text -match 'Software Off|Hardware Off|powered down') {
        $enabled = $false
    }

    if ($snapshot.State -match 'disabled|not ready') {
        $enabled = $false
    }

    [pscustomobject]@{
        Exists      = $true
        Enabled     = $enabled
        Name        = $snapshot.Name
        State       = $snapshot.State
        CurrentSsid = $snapshot.CurrentSsid
    }
}

function Get-CurrentSsid {
    $snapshot = Get-WifiInterfaceSnapshot
    if (-not $snapshot.Exists) {
        return $null
    }

    if ($snapshot.State -notmatch 'connected') {
        return $null
    }

    $snapshot.CurrentSsid
}

function Test-IsCampusWifi {
    param(
        [Parameter(Mandatory = $true)][string]$Ssid,
        [Parameter(Mandatory = $true)][object]$Config
    )

    foreach ($candidate in $Config.campusSsids) {
        if ($Ssid -eq [string]$candidate) {
            return $true
        }
    }

    return $false
}

function Get-CampusWifiState {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [scriptblock]$StatusCallback
    )

    Invoke-CampusWifiStatus -Message 'Checking Wi-Fi adapter.' -StatusCallback $StatusCallback
    $wifi = Get-WifiStatus
    if (-not $wifi.Exists) {
        return [pscustomobject]@{ State = 'NoWifiAdapter'; Reason = 'No Wi-Fi adapter detected.'; CurrentSsid = $null; PortalContext = $null }
    }

    if (-not $wifi.Enabled) {
        return [pscustomobject]@{ State = 'WifiOff'; Reason = 'Wi-Fi is turned off.'; CurrentSsid = $null; PortalContext = $null }
    }

    Invoke-CampusWifiStatus -Message 'Checking current Wi-Fi connection.' -StatusCallback $StatusCallback
    $ssid = [string]$wifi.CurrentSsid
    if (-not $ssid) {
        return [pscustomobject]@{ State = 'NoWifiConnection'; Reason = 'Not connected to any Wi-Fi network.'; CurrentSsid = $null; PortalContext = $null }
    }

    Invoke-CampusWifiStatus -Message "Connected SSID: $ssid" -StatusCallback $StatusCallback
    if (-not (Test-IsCampusWifi -Ssid $ssid -Config $Config)) {
        return [pscustomobject]@{ State = 'OtherWifiConnected'; Reason = 'Current Wi-Fi is not a campus network.'; CurrentSsid = $ssid; PortalContext = $null }
    }

    $baseUrl = [string]$Config.auth.baseUrl
    if (-not $baseUrl) {
        $baseUrl = Get-PortalBaseUrl -Config $Config -PortalUrl ([string]$Config.auth.portalPageUrl)
    }

    $status = $null
    try {
        Invoke-CampusWifiStatus -Message 'Checking campus portal online status.' -StatusCallback $StatusCallback
        $status = Get-OnlineStatus -BaseUrl $baseUrl -TimeoutSeconds ([int]$Config.timeoutSeconds)
    } catch {
        Invoke-CampusWifiStatus -Message "Online status check failed before login: $($_.Exception.Message)" -StatusCallback $StatusCallback
    }

    if ($status -and [string]$status.error -eq 'ok') {
        return [pscustomobject]@{ State = 'CampusWifiOnline'; Reason = 'Campus portal already reports online.'; CurrentSsid = $ssid; PortalContext = $null }
    }

    Invoke-CampusWifiStatus -Message 'Checking whether captive portal authentication is required.' -StatusCallback $StatusCallback
    $check = Get-PortalCheckResult -Config $Config
    if (-not $check.NeedsAuth) {
        return [pscustomobject]@{ State = 'CampusWifiOnline'; Reason = 'Internet connectivity is already available.'; CurrentSsid = $ssid; PortalContext = $null }
    }

    $fallbackIp = if ($status -and $status.client_ip) { [string]$status.client_ip } else { $null }
    $portalContext = Get-PortalContext -Config $Config -PortalUrl $check.PortalUrl -FallbackIp $fallbackIp
    [pscustomobject]@{ State = 'CampusWifiNeedsAuth'; Reason = 'Captive portal authentication required.'; CurrentSsid = $ssid; PortalContext = $portalContext }
}

function Test-CampusWifiNeedAuth {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [scriptblock]$StatusCallback
    )

    $state = Get-CampusWifiState -Config $Config -StatusCallback $StatusCallback
    [pscustomobject]@{
        ShouldAuthenticate = $state.State -eq 'CampusWifiNeedsAuth'
        Reason             = $state.Reason
        PortalContext      = $state.PortalContext
        CurrentSsid        = $state.CurrentSsid
        State              = $state.State
    }
}

function Test-CampusWifiAutoStartNeedAction {
    param([Parameter(Mandatory = $true)][object]$Config)

    $state = Get-CampusWifiState -Config $Config
    $state.State -eq 'CampusWifiNeedsAuth'
}
function New-Timestamp { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

function New-Callback {
    param([Parameter(Mandatory = $true)][long]$Timestamp)
    "jQuery11240$(Get-Random -Minimum 100000 -Maximum 999999)_$Timestamp"
}

function ConvertTo-QueryString {
    param([Parameter(Mandatory = $true)][hashtable]$Parameters)

    $pairs = foreach ($key in $Parameters.Keys) {
        $encodedKey = [System.Uri]::EscapeDataString([string]$key)
        $encodedValue = [System.Uri]::EscapeDataString([string]$Parameters[$key])
        "$encodedKey=$encodedValue"
    }

    $pairs -join '&'
}

function Invoke-UrlEncodedGet {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $query = ConvertTo-QueryString -Parameters $Parameters
    $uri = "${BaseUrl}?$query"
    Invoke-WebRequest -Uri $uri -Method Get -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
}

function Get-JsonpPayload {
    param([Parameter(Mandatory = $true)][string]$Text)
    $trimmed = $Text.Trim()
    $start = $trimmed.IndexOf('(')
    $end = $trimmed.LastIndexOf(')')
    if ($start -lt 0 -or $end -le $start) {
        throw 'Unexpected JSONP response format.'
    }
    $trimmed.Substring($start + 1, $end - $start - 1)
}

function ConvertFrom-Jsonp {
    param([Parameter(Mandatory = $true)][string]$Text)
    Get-JsonpPayload -Text $Text | ConvertFrom-Json
}

function Get-QueryParams {
    param([Parameter(Mandatory = $true)][string]$Url)

    $result = @{}
    $uri = [System.Uri]$Url
    $query = $uri.Query.TrimStart('?')
    if (-not $query) {
        return $result
    }

    foreach ($pair in $query.Split('&')) {
        if (-not $pair) { continue }
        $parts = $pair.Split('=', 2)
        $name = [System.Uri]::UnescapeDataString($parts[0])
        $value = if ($parts.Count -gt 1) { [System.Uri]::UnescapeDataString($parts[1]) } else { '' }
        $result[$name] = $value
    }

    $result
}

function Get-PortalBaseUrl {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [string]$PortalUrl
    )

    if ($PortalUrl) {
        $uri = [System.Uri]$PortalUrl
        return "{0}://{1}" -f $uri.Scheme, $uri.Authority
    }

    [string]$Config.auth.baseUrl
}

function Get-PortalCheckResult {
    param([Parameter(Mandatory = $true)][object]$Config)

    $isRedirected = $false
    $finalUrl = [string]$Config.auth.portalPageUrl
    $content = ''

    try {
        $response = Invoke-WebRequest -Uri $Config.networkTestUrl -MaximumRedirection 0 -TimeoutSec ([int]$Config.timeoutSeconds) -UseBasicParsing -ErrorAction Stop
        $finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri
        $content = [string]$response.Content
    } catch {
        $webResponse = $null
        if ($_.Exception -and $_.Exception.PSObject.Properties['Response']) {
            $webResponse = $_.Exception.Response
        }

        if ($webResponse -and $webResponse.Headers['Location']) {
            $isRedirected = $true
            $finalUrl = [string]$webResponse.Headers['Location']
        } else {
            $isRedirected = $true
            $finalUrl = [string]$Config.auth.portalPageUrl
        }
    }

    $expectedContent = [string]$Config.expectedNetworkTestContent
    $needsAuth = $isRedirected -or ($content -notlike "*$expectedContent*")

    [pscustomobject]@{ NeedsAuth = $needsAuth; PortalUrl = $finalUrl; Content = $content }
}

function Get-OnlineStatus {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $timestamp = New-Timestamp
    $response = Invoke-UrlEncodedGet -BaseUrl "${BaseUrl}/cgi-bin/rad_user_info" -TimeoutSeconds $TimeoutSeconds -Parameters @{ callback = New-Callback -Timestamp $timestamp; _ = $timestamp }
    ConvertFrom-Jsonp -Text ([string]$response.Content)
}

function Get-PortalContext {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [string]$PortalUrl,
        [string]$FallbackIp
    )

    $effectivePortalUrl = if ($PortalUrl) { $PortalUrl } else { [string]$Config.auth.portalPageUrl }
    $baseUrl = Get-PortalBaseUrl -Config $Config -PortalUrl $effectivePortalUrl
    $queryParams = if ($effectivePortalUrl) { Get-QueryParams -Url $effectivePortalUrl } else { @{} }

    $ip = [string]$queryParams['wlanuserip']
    if (-not $ip) { $ip = [string]$queryParams['userip'] }
    if (-not $ip) { $ip = $FallbackIp }
    if (-not $ip) { $ip = [string]$Config.auth.ip }

    $acId = [string]$queryParams['ac_id']
    if (-not $acId) { $acId = [string]$Config.auth.acId }

    if (-not $ip) { throw 'Could not determine campus portal IP address.' }
    if (-not $acId) { throw 'Could not determine ac_id for the campus portal.' }

    [pscustomobject]@{ BaseUrl = $baseUrl; PortalUrl = $effectivePortalUrl; Ip = $ip; AcId = $acId }
}

function Get-HmacMd5Hex {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $hmac = [System.Security.Cryptography.HMACMD5]::new([System.Text.Encoding]::UTF8.GetBytes($Key))
    try {
        $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
    } finally {
        $hmac.Dispose()
    }

    ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Get-Sha1Hex {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
    } finally {
        $sha1.Dispose()
    }

    ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function ConvertTo-SrunBase64 {
    param([Parameter(Mandatory = $true)][string]$BinaryString)

    $bytes = New-Object byte[] $BinaryString.Length
    for ($i = 0; $i -lt $BinaryString.Length; $i++) {
        $bytes[$i] = [byte]([int][char]$BinaryString[$i] -band 0xFF)
    }

    $standard = [System.Convert]::ToBase64String($bytes)
    $sourceAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    $targetAlphabet = 'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA'

    $builder = [System.Text.StringBuilder]::new()
    foreach ($charValue in $standard.ToCharArray()) {
        if ($charValue -eq '=') {
            [void]$builder.Append('=')
            continue
        }
        $index = $sourceAlphabet.IndexOf($charValue)
        if ($index -lt 0) { throw "Unexpected base64 character: $charValue" }
        [void]$builder.Append($targetAlphabet[$index])
    }

    $builder.ToString()
}

function Get-SrunXEncode {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$Key
    )

    [SrunCodec]::XEncode($Message, $Key)
}

function Get-SrunInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Ip,
        [Parameter(Mandatory = $true)][string]$AcId,
        [Parameter(Mandatory = $true)][string]$EncVer,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $infoObject = [ordered]@{ username = $Username; password = $Password; ip = $Ip; acid = $AcId; enc_ver = $EncVer }
    $infoJson = $infoObject | ConvertTo-Json -Compress
    $encoded = Get-SrunXEncode -Message $infoJson -Key $Token
    '{SRBX1}' + (ConvertTo-SrunBase64 -BinaryString $encoded)
}

function Get-SrunChallenge {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Ip,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $timestamp = New-Timestamp
    $response = Invoke-UrlEncodedGet -BaseUrl "${BaseUrl}/cgi-bin/get_challenge" -TimeoutSeconds $TimeoutSeconds -Parameters @{ callback = New-Callback -Timestamp $timestamp; username = $Username; ip = $Ip; _ = $timestamp }
    ConvertFrom-Jsonp -Text ([string]$response.Content)
}

function Invoke-SrunLogin {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][object]$Credentials,
        [Parameter(Mandatory = $true)][object]$PortalContext
    )

    $challenge = Get-SrunChallenge -BaseUrl $PortalContext.BaseUrl -Username $Credentials.StudentId -Ip $PortalContext.Ip -TimeoutSeconds ([int]$Config.timeoutSeconds)
    $token = [string]$challenge.challenge
    if (-not $token) { throw 'Challenge token was not returned by the portal.' }

    $hmd5 = Get-HmacMd5Hex -Key $token -Value $Credentials.Password
    $encVer = [string]$Config.auth.encVer
    if (-not $encVer) { $encVer = 'srun_bx1' }

    $info = Get-SrunInfo -Username $Credentials.StudentId -Password $Credentials.Password -Ip $PortalContext.Ip -AcId $PortalContext.AcId -EncVer $encVer -Token $token
    $n = [string]$Config.auth.n
    $type = [string]$Config.auth.type
    $checksumSource = $token + $Credentials.StudentId + $token + $hmd5 + $token + $PortalContext.AcId + $token + $PortalContext.Ip + $token + $n + $token + $type + $token + $info
    $checksum = Get-Sha1Hex -Value $checksumSource

    $timestamp = New-Timestamp
    $response = Invoke-UrlEncodedGet -BaseUrl "$($PortalContext.BaseUrl)/cgi-bin/srun_portal" -TimeoutSeconds ([int]$Config.timeoutSeconds) -Parameters @{
        callback     = New-Callback -Timestamp $timestamp
        action       = 'login'
        username     = $Credentials.StudentId
        password     = '{MD5}' + $hmd5
        os           = [string]$Config.auth.os
        name         = [string]$Config.auth.name
        double_stack = [string]$Config.auth.doubleStack
        chksum       = $checksum
        info         = $info
        ac_id        = $PortalContext.AcId
        ip           = $PortalContext.Ip
        n            = $n
        type         = $type
        _            = $timestamp
    }

    ConvertFrom-Jsonp -Text ([string]$response.Content)
}


function Invoke-CampusWifiLogin {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][object]$Credentials,
        [scriptblock]$StatusCallback
    )

    Invoke-CampusWifiStatus -Message 'Starting campus Wi-Fi workflow.' -StatusCallback $StatusCallback

    $state = Get-CampusWifiState -Config $Config -StatusCallback $StatusCallback
    switch ($state.State) {
        'CampusWifiOnline' {
            Invoke-CampusWifiStatus -Message $state.Reason -StatusCallback $StatusCallback
            return [pscustomobject]@{ Success = $true; Message = $state.Reason }
        }
        'CampusWifiNeedsAuth' {
            $portalContext = $state.PortalContext
        }
        default {
            Invoke-CampusWifiStatus -Message $state.Reason -StatusCallback $StatusCallback
            return [pscustomobject]@{ Success = $false; Message = $state.Reason }
        }
    }

    Invoke-CampusWifiStatus -Message "Opening campus portal: $($portalContext.PortalUrl)" -StatusCallback $StatusCallback
    Invoke-CampusWifiStatus -Message 'Preparing encrypted login payload.' -StatusCallback $StatusCallback
    $loginResponse = Invoke-SrunLogin -Config $Config -Credentials $Credentials -PortalContext $portalContext
    Invoke-CampusWifiStatus -Message "Portal response: $([string]$loginResponse.error)" -StatusCallback $StatusCallback

    Start-Sleep -Seconds 2
    Invoke-CampusWifiStatus -Message 'Verifying final online status.' -StatusCallback $StatusCallback
    $postStatus = Get-OnlineStatus -BaseUrl $portalContext.BaseUrl -TimeoutSeconds ([int]$Config.timeoutSeconds)
    if ([string]$postStatus.error -eq 'ok') {
        Invoke-CampusWifiStatus -Message 'Authentication succeeded.' -StatusCallback $StatusCallback
        return [pscustomobject]@{ Success = $true; Message = 'Authentication succeeded.' }
    }

    Invoke-CampusWifiStatus -Message 'Authentication request finished, but final online status is not confirmed.' -StatusCallback $StatusCallback
    [pscustomobject]@{ Success = $false; Message = 'Authentication request finished, but final online status is not confirmed.' }
}

Export-ModuleMember -Function Get-CampusWifiPaths, Write-CampusWifiLog, Get-CampusWifiConfig, Save-CampusWifiConfig, Get-CampusWifiSavedState, Save-CampusWifiAppSettings, Get-CampusWifiRuntimeCredential, Set-CampusWifiStartupEnabled, Install-CampusWifiDesktopShortcut, Get-WifiStatus, Get-CurrentSsid, Test-IsCampusWifi, Get-CampusWifiState, Test-CampusWifiNeedAuth, Test-CampusWifiAutoStartNeedAction, Invoke-CampusWifiLogin
