#Requires -Version 5.1
[CmdletBinding()]
param(
  # 不再 Mandatory：留空时按 -Preset 回落官方直链，杜绝 "-Url ''" 绑定失败
  [string]$Url = '',
  [ValidateSet('vs2008', 'sdk71', 'kb', '')][string]$Preset = '',
  [Parameter(Mandatory=$true)][string]$OutFile,
  [string]$Sha1 = '',
  [string]$MinBytes = '100MB',
  [switch]$AllowExe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------- 官方预设（微软下载中心至今在线，零第三方存档）----------
# 用户换源时用 -Url 覆盖；-Url 留空则按 Preset 取官方直链。
$PresetTable = @{
  'vs2008' = @{
    Url      = 'https://download.microsoft.com/download/1/9/d/19d22169-a4b2-455f-8c28-ed137bd91487/VS2008SP1CHSX1512981.iso'
    Sha1     = ''   # 用户提供时经 -Sha1 覆盖；官方页面未给稳定 SHA1，默认只记录不校验
    MinBytes = '800MB'
  }
  'sdk71'  = @{
    Url      = 'https://download.microsoft.com/download/A/6/A/A6AC035D-DA3F-4F0C-ADA4-37C8E5D34E3D/GRMSDKX_EN_DVD.iso'
    Sha1     = '9203529F5F70D556A60C37F118A95214E6D10B5A'
    MinBytes = '500MB'
  }
  'kb'     = @{
    Url      = 'https://download.microsoft.com/download/0/B/D/0BDA894F-2CCD-4C2C-B5A7-4EB1171962E5/vc-compiler-kb2519277.exe'
    Sha1     = ''
    MinBytes = '100MB'
  }
}

# ---------- 解析最终 Url / Sha1 / MinBytes（空串一律回落预设）----------
if ([string]::IsNullOrWhiteSpace($Url) -and $Preset -ne '') {
  $Url = $PresetTable[$Preset].Url
  if ([string]::IsNullOrWhiteSpace($Sha1)) { $Sha1 = $PresetTable[$Preset].Sha1 }
  if ($MinBytes -eq '100MB')              { $MinBytes = $PresetTable[$Preset].MinBytes }
}
if ([string]::IsNullOrWhiteSpace($Url)) {
  throw "未指定下载地址：请用 -Preset vs2008|sdk71，或显式 -Url <直链>。"
}

$min = [int64](Invoke-Expression $MinBytes)

if ($Url -notmatch '^https://download\.microsoft\.com/') {
  Write-Warning "下载源不是 download.microsoft.com 官方域名：$Url"
} else {
  Write-Host "==> 源：$Url" -ForegroundColor DarkGray
}

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if ($OutFile -notmatch '\.(iso|exe)$') { throw "OutFile 必须是 .iso 或 .exe：$OutFile" }
if ($OutFile -match '\.exe$' -and -not $AllowExe) { throw "禁止下载 exe（需要请加 -AllowExe）" }

# ---------- 命中缓存则跳过下载（同一 runner 重复跑省时间）----------
if (Test-Path $OutFile) {
  $exists = Get-Item $OutFile
  if ($exists.Length -ge $min) {
    Write-Host ("==> 命中缓存，跳过下载：{0}  {1:N1} MB" -f $exists.Name, ($exists.Length / 1MB)) -ForegroundColor Green
    return
  }
  Write-Warning "缓存文件体积不足，重新下载。"
}

# ---------- 带重试 + 续传的下载 ----------
$maxRetry = 5
$ok = $false
for ($i = 1; $i -le $maxRetry; $i++) {
  try {
    Write-Host "==> 下载 [$i/$maxRetry] $Url" -ForegroundColor Cyan
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
    $wc.DownloadFile($Url, $OutFile)
    $wc.Dispose()
    $ok = $true
    break
  } catch {
    Write-Warning "第 $i 次下载失败： $($_.Exception.Message)"
    if ($i -lt $maxRetry) { Start-Sleep -Seconds ([math]::Min(30 * $i, 120)) }
  }
}
if (-not $ok) { throw "下载失败（已重试 $maxRetry 次）：$Url" }

# ---------- 体积校验 ----------
$fi = Get-Item $OutFile
if ($fi.Length -lt $min) {
  throw "文件体积异常：$($fi.Length) 字节，小于预期 $min（可能是错误页/截断）。请检查直链是否仍有效。"
}
Write-Host ("==> 下载完成：{0}  {1:N1} MB" -f $fi.Name, ($fi.Length / 1MB))

# ---------- SHA1 校验 ----------
if ($Sha1 -and $Sha1.Trim()) {
  Write-Host "==> 校验 SHA1（期望 $Sha1）" -ForegroundColor Cyan
  $actual = (Get-FileHash -Path $OutFile -Algorithm SHA1).Hash.ToUpperInvariant()
  $expect = $Sha1.Trim().ToUpperInvariant()
  if ($actual -ne $expect) {
    Remove-Item $OutFile -Force
    throw "SHA1 不匹配！实际=$actual 期望=$expect —— 文件已删除，请换官方源重下。"
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
