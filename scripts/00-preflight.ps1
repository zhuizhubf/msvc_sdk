#Requires -Version 5.1
[CmdletBinding()]
param([switch]$RequireDotNet4)
$ErrorActionPreference = 'Stop'
Write-Host "==> 预检 runner 环境" -ForegroundColor Cyan
$os = (Get-CimInstance Win32_OperatingSystem)
Write-Host ("    OS: {0} {1}" -f $os.Caption, $os.Version)

# .NET 4（SDK 7.1 装 VC 编译器组件的前置条件）
$ndp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
if ($ndp -and $ndp.Release -ge 378389) {
  Write-Host "    .NET 4.x: OK (Release $($ndp.Release))" -ForegroundColor Green
} else {
  if ($RequireDotNet4) { throw "需要 .NET Framework 4.x 但没找到——SDK 7.1 会静默跳过 VC 编译器组件" }
  Write-Warning "    .NET 4.x 未检出（2008 包不强依赖，2010 包必须）"
}

# 7-Zip（ISO 解压回退方案）
$7z = Get-Command 7z -ErrorAction SilentlyContinue
if ($7z) { Write-Host "    7-Zip  : OK ($($7z.Source))" } else { Write-Warning "    7-Zip 未找到（用 Mount-DiskImage 即可，不影响）" }

# 磁盘空间（需要容纳 2 个 ISO + 安装 + 产物 ≈ 12GB）
$free = (Get-PSDrive C).Free / 1GB
Write-Host ("    磁盘C  : 剩余 {0:N1} GB" -f $free)
if ($free -lt 15) { throw "C: 剩余空间不足 15GB，无法完成安装" }

# 管理员权限（安装器需要）
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) { Write-Host "    权限    : Administrator OK" -ForegroundColor Green } else { Write-Warning "    当前非管理员（GitHub runner 默认是，若本地跑需提权）" }
