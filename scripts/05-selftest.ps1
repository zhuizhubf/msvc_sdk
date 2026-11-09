#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Root,
  [Parameter(Mandatory=$true)][ValidateSet('x86','x64')][string]$Arch,
  [int]$ExpectMscVer = 1500
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$clenv = Join-Path $Root 'clenv.bat'
if (-not (Test-Path $clenv)) { throw "绿色包缺 clenv.bat：$Root" }

$src = Join-Path $PSScriptRoot '..\src\hello.cpp'
if (-not (Test-Path $src)) { $src = Join-Path $Root '..\src\hello.cpp' }
if (-not (Test-Path $src)) { throw "找不到 hello.cpp" }

$work = Join-Path $Root '_selftest'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null
Copy-Item $src (Join-Path $work 'hello.cpp') -Force

Write-Host "==> 自检 $Arch（期望 _MSC_VER=$ExpectMscVer）" -ForegroundColor Cyan
$bat = @"
@echo off
call "$clenv" $Arch
if errorlevel 1 exit /b 1
cd /d "$work"
cl /nologo /EHsc /MT hello.cpp || exit /b 2
hello.exe || exit /b 3
"@
$batPath = Join-Path $work 'run.bat'
Set-Content -Path $batPath -Value $bat -Encoding ASCII

& $batPath
$code = $LASTEXITCODE
if ($code -ne 0) { throw "自检失败，退出码 $code" }

$out = Get-Content (Join-Path $work 'hello.out.txt') -ErrorAction SilentlyContinue
if ($out -match "ver\.\s*(\d+)") {
  $ver = [int]$matches[1]
  if ($ver -ne $ExpectMscVer) { throw "_MSC_VER 不符：实际 $ver，期望 $ExpectMscVer" }
  Write-Host "==> 自检通过：_MSC_VER = $ver" -ForegroundColor Green
}
Write-Host "==> 编译器与运行均正常，绿色包可用" -ForegroundColor Green
