param(
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ProjectFile = Join-Path $ProjectRoot 'src\HZNUCampusWifiAssistant\HZNUCampusWifiAssistant.csproj'
$OutputDirectory = Join-Path $ProjectRoot "artifacts\publish\$Runtime"
$LocalDotnet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'

$DotnetCommand = (Get-Command dotnet -ErrorAction SilentlyContinue)?.Source
if (-not $DotnetCommand -and (Test-Path $LocalDotnet)) {
    $DotnetCommand = $LocalDotnet
}

if (-not $DotnetCommand) {
    throw '未检测到 dotnet SDK。请先安装 .NET 8 SDK。'
}

& $DotnetCommand restore $ProjectFile -r $Runtime
& $DotnetCommand publish $ProjectFile `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    --no-restore `
    /p:PublishSingleFile=true `
    /p:IncludeNativeLibrariesForSelfExtract=true `
    /p:PublishTrimmed=false `
    -o $OutputDirectory

Write-Host "发布完成：$OutputDirectory"
