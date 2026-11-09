#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Url,
  [Parameter(Mandatory=$true)][string]$OutFile,
  [string]$Sha1 = '',
  [string]$MinBytes = '100MB',
  [switch]$AllowExe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$min = [int64](Invoke-Expression $MinBytes)

if ($Url -notmatch '^https://download\.microsoft\.com/') {
  Write-Warning "下载源不是 download.microsoft.com 官方域名：$Url"
}

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

if ($OutFile -notmatch '\.(iso|exe)$') { throw "OutFile 必须是 .iso 或 .exe：$OutFile" }
if ($OutFile -match '\.exe$' -and -not $AllowExe) { throw "禁止下载 exe（需要请加 -AllowExe）" }

# ---------- 带重试 + 续传的下载 ----------
$maxRetry = 5
$ok = $false
for ($i = 1; $i -le $maxRetry; $i++) {
  try {
    Write-Host "==> 下载 [$i/$maxRetry] $Url" -ForegroundColor Cyan
    # 用 BITS 不可用时退回 WebClient；这里统一用 .NET WebClient 保证 runner 兼容
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

# ---------- Authenticode 验签（仅 exe） ----------
if ($OutFile -match '\.exe$') {
  try {
    $sig = Get-AuthenticodeSignature $OutFile
    Write-Host "==> 签名状态：$($sig.Status)  签署者：$($sig.SignerCertificate.Subject)"
    if ($sig.Status -ne 'Valid') { Write-Warning "exe 签名无效，请人工确认来源" }
  } catch { Write-Warning "验签失败：$($_.Exception.Message)" }
}
