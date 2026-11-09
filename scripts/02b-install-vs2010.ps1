#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$IsoPath,
  [string]$LogDir = "$env:TEMP\vs2010-setup"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path $IsoPath)) { throw "找不到 VS2010 ISO：$IsoPath" }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# 挂载 ISO（windows runner 支持 Mount-DiskImage）
$img = Mount-DiskImage -ImagePath $IsoPath -PassThru
$drive = ($img | Get-Volume).DriveLetter
if (-not $drive) { throw "ISO 挂载失败：$IsoPath" }
Write-Host "==> ISO 挂载到 ${drive}:"

try {
  # 与 VS2008 一样：必须进 Setup 子目录，根目录 setup.hta 不认 /q
  $setup = "${drive}:\Setup\Setup.exe"
  if (-not (Test-Path $setup)) { $setup = "${drive}:\setup.exe" }
  if (-not (Test-Path $setup)) { throw "ISO 内找不到 Setup.exe" }

  $args = @('/q', '/norestart', "/Log=$LogDir\vs2010-install.log")
  Write-Host "==> 静默安装 VS2010：$setup $($args -join ' ')" -ForegroundColor Cyan
  $p = Start-Process -FilePath $setup -ArgumentList $args -Wait -PassThru -NoNewWindow
  Write-Host "==> Setup.exe 退出码：$($p.ExitCode)"

  # VS2010 安装器会 spawn 子进程，退出码 0/3010 均视为成功
  if ($p.ExitCode -notin 0, 3010) {
    Write-Warning "退出码非 0/3010，检查日志：$LogDir"
  } else {
    Write-Host "==> VS2010 安装完成（退出码 $($p.ExitCode)）" -ForegroundColor Green
  }
}
finally {
  Dismount-DiskImage -ImagePath $IsoPath | Out-Null
  Write-Host "==> ISO 已卸载"
}
