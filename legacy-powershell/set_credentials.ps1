$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$credentialPath = Join-Path $scriptDir 'credential.xml'

$studentId = Read-Host '请输入学号'
$password = Read-Host '请输入统一身份认证密码' -AsSecureString

$credential = New-Object System.Management.Automation.PSCredential($studentId, $password)
$credential | Export-Clixml -LiteralPath $credentialPath

Write-Host "凭据已保存到: $credentialPath"
Write-Host '该文件只能由当前 Windows 用户在当前电脑上解密。'
