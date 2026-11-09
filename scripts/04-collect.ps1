#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('2008','2010')][string]$Toolset,
  [Parameter(Mandatory=$true)][ValidateSet('x86','x64')][string]$Arch,
  [Parameter(Mandatory=$true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$pf86 = ${env:ProgramFiles(x86)}
if (-not $pf86) { $pf86 = 'C:\Program Files (x86)' }
$sdkRoot = Join-Path $pf86 'Microsoft SDKs\Windows'

if ($Toolset -eq '2008') {
  $vcDir = Join-Path $pf86 'Microsoft Visual Studio 9.0\VC'
  $sdkVer = 'v6.0A'     # VS2008 SP1 官方搭配版本
  $mscVer = 1500
} else {
  $vcDir = Join-Path $pf86 'Microsoft Visual Studio 10.0\VC'
  $sdkVer = 'v7.1A'     # SDK 7.1 的 v7.1A 目录；不存在则回落 v7.1
  $mscVer = 1600
}

foreach ($p in @($vcDir)) {
  if (-not (Test-Path $p)) { throw "缺少目录：$p （对应 VS$Toolset 未装成功？）" }
}
$sdkDir = Join-Path $sdkRoot $sdkVer
if (-not (Test-Path $sdkDir)) {
  $fb = Join-Path $sdkRoot 'v7.1'
  if (Test-Path $fb) { $sdkDir = $fb; $sdkVer = 'v7.1' }
  else { throw "缺少 SDK 目录：$sdkDir（也没有 v7.1 回落目录）" }
}

Write-Host "==> VC   : $vcDir"
Write-Host "==> SDK  : $sdkDir  ($sdkVer)"
Write-Host "==> 输出 : $OutDir"

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir 'VC')   -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir 'SDK')  -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir 'bin')  -Force | Out-Null

# ---------- 拷贝 VC 编译器 ----------
Copy-Item (Join-Path $vcDir 'bin')      (Join-Path $OutDir 'VC\bin')      -Recurse -Force
Copy-Item (Join-Path $vcDir 'include')  (Join-Path $OutDir 'VC\include') -Recurse -Force
Copy-Item (Join-Path $vcDir 'lib')      (Join-Path $OutDir 'VC\lib')     -Recurse -Force
Copy-Item (Join-Path $vcDir 'atlmfc')   (Join-Path $OutDir 'VC\atlmfc')  -Recurse -Force -ErrorAction SilentlyContinue

# ---------- 拷贝 SDK 头/库/工具 ----------
foreach ($sub in 'Include','Lib','Bin') {
  $src = Join-Path $sdkDir $sub
  if (Test-Path $src) { Copy-Item $src (Join-Path $OutDir "SDK\$sub") -Recurse -Force }
}

# ---------- 生成绕开注册表的环境引导 ----------
$clenv = @"
@echo off
REM === MSVC $Toolset 便携环境（纯环境变量，不依赖注册表，官方 vcvarsall.bat 不可用时的替代）===
set MSVC_PORTABLE=1
set MSVC_TOOLSET=$Toolset
set _ROOT=%~dp0
if /I "%1"=="x64" (set _ARCH=amd64) else (set _ARCH=x86)

set PATH=%_ROOT%SDK\Bin;%_ROOT%VC\bin;%_ARCH%;%_ROOT%VC\bin;%PATH%
set INCLUDE=%_ROOT%SDK\Include;%_ROOT%VC\include;%_ROOT%VC\atlmfc\include
set LIB=%_ROOT%SDK\Lib\%_ARCH%;%_ROOT%VC\lib\%_ARCH%

where cl.exe >nul 2>nul || (echo [FATAL] cl.exe 不在 PATH，请检查目录结构 & exit /b 1)
cl.exe 2>&1 | findstr /i "$mscVer" >nul && echo [OK] MSVC $Toolset ready ^(x86/x64 = %_ARCH%^)
"@
Set-Content -Path (Join-Path $OutDir 'clenv.bat') -Value $clenv -Encoding ASCII

# ---------- 编译包装：默认 /MT 静态链 CRT，产物不依赖目标机 VC 运行库 ----------
$build = @"
@echo off
REM 用法： build.bat x86 hello.cpp        （默认 /MT 静态 CRT）
call "%~dp0clenv.bat" %1
shift
cl.exe /nologo /EHsc /MT %*
"@
Set-Content -Path (Join-Path $OutDir 'build.bat') -Value $build -Encoding ASCII

# ---------- README ----------
$readme = @"
# MSVC $Toolset 便携包（自动生成，请勿手改 clenv.bat/build.bat）

## 用法（任意 Windows 机，无需安装 VS、无需管理员）
    clenv.bat x86            :: 初始化 x86 环境（或 x64）
    build.bat x86 hello.cpp  :: 默认 /MT 静态链 CRT
    或： clenv.bat x86 && cl /EHsc /MT hello.cpp

## 说明
- clenv.bat 纯靠 PATH/INCLUDE/LIB 三个环境变量，**不读注册表**，
  因此在没有安装过 VS 的机器/容器里也能用（这是官方 vcvarsall.bat 做不到的）。
- 默认 /MT 静态链接 CRT，产物无需目标机安装 VC$Toolset 运行库。
  若需动态链，把 build.bat 里的 /MT 改成 /MD（目标机需装对应 redist）。
- 编译器来源：Windows SDK 7.1（微软官方） / VS2008 SP1 ISO（微软官方）。
- 仅用于编译原生 C/C++；若需 MFC/ATL 请确认已随 VS$Toolset ISO 一并收集。

## 验证成功标志
运行 clenv.bat 后看到： [OK] MSVC $Toolset ready
hello 程序输出：        compiler ver. $mscVer
"@
Set-Content -Path (Join-Path $OutDir 'README.md') -Value $readme -Encoding UTF8

# ---------- 清单 ----------
$manifest = [ordered]@{
  toolset = $Toolset
  arch_default = $Arch
  msc_ver = $mscVer
  vc_dir = $vcDir
  sdk_dir = $sdkDir
  built_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  runner_os = 'windows-2022'
}
$manifest | ConvertTo-Json | Set-Content -Path (Join-Path $OutDir 'manifest.json') -Encoding UTF8

Write-Host "==> 收集完成" -ForegroundColor Green
Get-ChildItem $OutDir | Select-Object Name, Mode
