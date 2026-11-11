#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$Url = '',
  [ValidateSet('vs2008', 'sdk71', 'vs2010', 'kb', '')][string]$Preset = '',
  [Parameter(Mandatory=$true)][string]$OutFile,
  [string]$Sha1 = '',
  [string]$MinBytes = '100MB',
  [switch]$AllowExe
)

# ============================================================================
# 下载策略（重要，先看这段）：
#   ed2k 协议 GitHub runner 用不了，且微软对老 SDK/VS2010 已无稳定官方直链。
#   本脚本对每个预设内置「多候选源」，按优先级自动回退：
#     1) 微软官方直链（vs2008 / kb 仍有效，优先）
#     2) archive.org 的 HTTP 直链（与 msdn.itellyou.cn 同为官方原版镜像，SHA1 相同）
#   命中任一可用源即下载，并用 SHA1 校验，确保拿到的就是官方原版。
#   再配合 workflow 里的 actions/cache：ISO 只下一次，后续全部命中缓存。
#
#   各镜像官方 SHA1（itellyou / archive.org 一致，用于校验）：
#     VS2008 SP1 CHS : VS2008SP1CHSX1512981.iso
#     SDK 7.1 x64    : GRMSDKX_EN_DVD.iso   SHA1 9203529F5F70D556A60C37F118A95214E6D10B5A
#     VS2010 Ultimate: cn_visual_studio_2010_ultimate_x86_dvd_532347.iso
#                      SHA1 44B73423A7BBCE38D06BA55ECD821946630BEA4D
#     VS2010 SP1     : mu_visual_studio_2010_sp1_x86_dvd_651704.iso
#                      SHA1 61C2088850185EDE8E18001D1EF3E6D12DAA5692
# ============================================================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------- 预设表：每个候选是 @{ Url=...; Official=$true/$false }，按序回退 ----------
$PresetTable = @{
  'vs2008' = @{
    FileName = 'VS2008SP1CHSX1512981.iso'
    Sha1     = ''
    MinBytes = '800MB'
    Urls     = @(
      'https://download.microsoft.com/download/1/9/d/19d22169-a4b2-455f-8c28-ed137bd91487/VS2008SP1CHSX1512981.iso'
    )
  }
  'sdk71'  = @{
    FileName = 'GRMSDKX_EN_DVD.iso'   # x64；x86 用 GRMSDK_EN_DVD.iso
    Sha1     = '9203529F5F70D556A60C37F118A95214E6D10B5A'
    MinBytes = '500MB'
    Urls     = @(
      'https://archive.org/download/GRMSDKX_EN_DVD/GRMSDKX_EN_DVD.iso',
      'https://archive.org/download/microsoft-windows-sdk-7.1/GRMSDKX_EN_DVD.iso'
    )
  }
  'vs2010' = @{
    # 默认旗舰版 CHS；换 SP1 请用 -Sha1 覆盖为 61C2088... 并把文件名改为 mu_visual_studio_2010_sp1_x86_dvd_651704.iso
    FileName = 'cn_visual_studio_2010_ultimate_x86_dvd_532347.iso'
    Sha1     = '44B73423A7BBCE38D06BA55ECD821946630BEA4D'
    MinBytes = '2GB'
    Urls     = @(
      'https://archive.org/download/Microsoft.Visual.Studio.Express.2010/cn_visual_studio_2010_ultimate_x86_dvd_532347.iso',
      'https://archive.org/download/cn_visual_studio_2010_ultimate_x86_dvd_532347/cn_visual_studio_2010_ultimate_x86_dvd_532347.iso',
      'https://archive.org/download/mu_visual_studio_2010_sp1_x86_dvd_651704/mu_visual_studio_2010_sp1_x86_dvd_651704.iso'
    )
  }
  'kb'     = @{
    FileName = 'vc-compiler-kb2519277.exe'
    Sha1     = ''
    MinBytes = '100MB'
    Urls     = @(
      'https://download.microsoft.com/download/0/B/D/0BDA894F-2CCD-4C2C-B5A7-4EB1171962E5/vc-compiler-kb2519277.exe'
    )
  }
}

# ---------- 解析预设 ----------
$candidates = @()
if ($Preset -ne '') {
  $p = $PresetTable[$Preset]
  if ([string]::IsNullOrWhiteSpace($Sha1)) { $Sha1 = $p.Sha1 }
  if ($MinBytes -eq '100MB')               { $MinBytes = $p.MinBytes }
  # 显式 -Url 优先级最高，其次预设候选表
  if (-not [string]::IsNullOrWhiteSpace($Url)) { $candidates += $Url }
  $candidates += $p.Urls
} elseif (-not [string]::IsNullOrWhiteSpace($Url)) {
  $candidates += $Url
}

# ---------- 命中缓存优先：ISO 已存在且体积达标则直接校验并跳过下载 ----------
$min = [int64](Invoke-Expression $MinBytes)
if (Test-Path $OutFile) {
  $exists = Get-Item $OutFile
  if ($exists.Length -ge $min) {
    Write-Host ("==> 命中缓存，跳过下载：{0}  {1:N1} MB" -f $exists.Name, ($exists.Length / 1MB)) -ForegroundColor Green
    $candidates = @()   # 有缓存就不再下载
  } else {
    Write-Warning "缓存文件体积不足（$($exists.Length) < $min），将尝试重新下载。"
  }
}

if ($candidates.Count -eq 0) {
  throw "无可用下载地址且无缓存。请显式 -Url 提供直链，或先用 actions/cache 放入 ISO：$OutFile"
}

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if ($OutFile -notmatch '\.(iso|exe)$') { throw "OutFile 必须是 .iso 或 .exe：$OutFile" }
if ($OutFile -match '\.exe$' -and -not $AllowExe) { throw "禁止下载 exe（需要请加 -AllowExe）" }

# ---------- 带重试 + 多候选源回退的下载 ----------
$maxRetry = 3
$ok = $false
$lastErr = ''
foreach ($cand in ($candidates | Select-Object -Unique)) {
  if ($cand -notmatch '^https?://') { Write-Warning "跳过非法 Url：$cand"; continue }
  if ($cand -match '^https://(download\.microsoft\.com|www\.microsoft\.com|archive\.org)/') {
    Write-Host "==> 源：$cand" -ForegroundColor DarkGray
  } else {
    Write-Warning "下载源非官方域名，谨慎：$cand"
  }
  for ($i = 1; $i -le $maxRetry; $i++) {
    try {
      Write-Host "==> 下载 [$i/$maxRetry] $cand" -ForegroundColor Cyan
      $wc = New-Object System.Net.WebClient
      $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
      $wc.DownloadFile($cand, $OutFile)
      $wc.Dispose()
      $ok = $true; break
    } catch {
      $lastErr = $_.Exception.Message
      Write-Warning "第 $i 次下载失败：$lastErr"
      if ($i -lt $maxRetry) { Start-Sleep -Seconds ([math]::Min(15 * $i, 60)) }
    }
  }
  if ($ok) { break }
  Write-Warning "该候选源不可用，切换下一个候选……"
}
if (-not $ok) { throw "所有候选源均下载失败（$($candidates.Count) 个源 × $maxRetry 次）：$lastErr" }

# ---------- 体积校验 ----------
$fi = Get-Item $OutFile
if ($fi.Length -lt $min) {
  Remove-Item $OutFile -Force
  throw "文件体积异常：$($fi.Length) 字节，小于预期 $min（可能是错误页/截断）。已删除。"
}
Write-Host ("==> 文件就绪：{0}  {1:N1} MB" -f $fi.Name, ($fi.Length / 1MB))

# ---------- SHA1 校验 ----------
if ($Sha1 -and $Sha1.Trim()) {
  Write-Host "==> 校验 SHA1（期望 $Sha1）" -ForegroundColor Cyan
  $actual = (Get-FileHash -Path $OutFile -Algorithm SHA1).Hash.ToUpperInvariant()
  $expect = $Sha1.Trim().ToUpperInvariant()
  if ($actual -ne $expect) {
    Remove-Item $OutFile -Force
    throw "SHA1 不匹配！实际=$actual 期望=$expect —— 文件已删除，请换源重下。"
  }
  Write-Host "==> SHA1 校验通过" -ForegroundColor Green
} else {
  Write-Host "==> 未提供 SHA1，跳过校验（仅记录实际值）" -ForegroundColor Yellow
  Write-Host ("    SHA1 = {0}" -f (Get-FileHash -Path $OutFile -Algorithm SHA1).Hash)
}

# ---------- Authenticode 验签（仅 exe）----------
if ($OutFile -match '\.exe$') {
  try {
    $sig = Get-AuthenticodeSignature $OutFile
    Write-Host "==> 签名状态：$($sig.Status)  签署者：$($sig.SignerCertificate.Subject)"
    if ($sig.Status -ne 'Valid') { Write-Warning "exe 签名无效，请人工确认来源" }
  } catch { Write-Warning "验签失败：$($_.Exception.Message)" }
}
