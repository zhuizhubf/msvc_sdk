#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Exe,
  [string]$LogDir = "$env:TEMP\kb2519277"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path $Exe)) { throw "找不到补丁：$Exe" }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

Write-Host "==> 应用 KB2519277（VC++ 2010 SP1 编译器更新）：$Exe" -ForegroundColor Cyan
$p = Start-Process -FilePath $Exe -ArgumentList @('/q', '/norestart') -Wait -PassThru -NoNewWindow
Write-Host "==> 退出码：$($p.ExitCode)"
if ($p.ExitCode -notin 0, 3010) {
  Write-Warning "补丁退出码非 0/3010（可能未安装 VS2010 SP1，此情况可忽略）"
} else {
  Write-Host "==> KB2519277 应用成功" -ForegroundColor Green
}
