# TadClip install with a paid code, Windows (spike: becomes install.ps1's first step). Same contract as gate-install.sh:
# TC1 codes are checked by the Sheet's web app, TC2 codes carry their key. Only what Windows 10/11 ships: .NET AES +
# SHA-256, Invoke-RestMethod, tar.exe. Then the usual installer runs on the unpacked copy (TADCLIP_SRC).
#   irm <url>/install.ps1 | iex        or   $env:TADCLIP_CODE='TC1-...'; irm ... | iex
& {
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Gate = if ($env:TADCLIP_GATE) { $env:TADCLIP_GATE } else { 'https://script.google.com/macros/s/AKfycbxXamYyB1J4OK5soi3HYRau9bkKvSpzZuVZzevri_w09xKLPhL6OgvE4uG8lznqbOi4/exec' }
$Meta = if ($env:TADCLIP_META) { $env:TADCLIP_META } else { 'https://raw.githubusercontent.com/npnatt12/tadclip-assets/main/release.json' }
$Cfg = Join-Path $env:APPDATA 'TadClip'; New-Item -ItemType Directory -Force -Path $Cfg | Out-Null
function Fail($m) { Write-Host ''; Write-Host ([char]0x2717 + ' ' + $m) }   # then 'return 1': exit would close the buyer's window (irm | iex)
function Hex($s) { [byte[]]($s -split '(..)' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }) }

$code = $env:TADCLIP_CODE
if (-not $code -and (Test-Path -LiteralPath "$Cfg\code")) { $code = (Get-Content -LiteralPath "$Cfg\code" -Raw) }
if (-not $code) { $code = Read-Host 'วางรหัส TadClip ที่ได้ทาง LINE แล้วกด Enter · paste your TadClip code' }
$code = ($code -replace '\s', '').ToUpper()

if ($code -like 'TC1-*') {
  try { $r = Invoke-RestMethod -Method Post -Uri $Gate -ContentType 'application/json' -Body ('{"code":"' + $code + '"}') -TimeoutSec 30 }
  catch { Fail 'เชื่อมต่อระบบตรวจรหัสไม่ได้ ลองวางบรรทัดเดิมอีกครั้งในอีกสักครู่ (ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE)'; return 1 }
  if (-not $r.ok) {
    switch ($r.why) {
      'expired' { Fail "รหัสนี้หมดอายุแล้ว (ใช้ได้ถึง $($r.until)) ต่ออายุได้ในกลุ่ม LINE"; return 1 }
      'revoked' { Fail 'รหัสนี้ถูกยกเลิกแล้ว ติดต่อทีมในกลุ่ม LINE'; return 1 }
      default   { Fail 'รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่ (คัดลอกทั้งบรรทัด ขึ้นต้นด้วย TC1-)'; return 1 }
    }
  }
  $key = $r.key; $iv = $r.iv; $sha = $r.sha256; $url = $r.url; $until = $r.until
} elseif ($code -match '^TC2-(\d{4})(\d{2})-([0-9A-F]{64})$') {
  $E = [int]$Matches[1] * 12 + [int]$Matches[2]; $until = "$($Matches[1])-$($Matches[2])"; $k = Hex $Matches[3].ToLower()
  try { $m = Invoke-RestMethod -Uri $Meta -TimeoutSec 30 } catch { Fail 'ดาวน์โหลดข้อมูลรุ่นไม่ได้ ลองวางบรรทัดเดิมอีกครั้ง'; return 1 }
  $n = $E - ([int]$m.month.Substring(0, 4) * 12 + [int]$m.month.Substring(5, 2))
  if ($n -lt 0) { Fail "รหัสนี้ใช้ได้ถึง $until แต่ TadClip รุ่นนี้ออกเดือน $($m.month): ต่ออายุได้ในกลุ่ม LINE"; return 1 }
  $h = [Security.Cryptography.SHA256]::Create(); for ($i = 0; $i -lt $n; $i++) { $k = $h.ComputeHash($k) }
  $key = -join ($k | ForEach-Object { $_.ToString('x2') }); $iv = $m.iv; $sha = $m.sha256; $url = $m.url
} else { Fail 'รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่ (ขึ้นต้นด้วย TC1- หรือ TC2-)'; return 1 }

$T = Join-Path $env:TEMP ('tadclip-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $T | Out-Null
try {
  Write-Host 'ดาวน์โหลด TadClip · downloading TadClip'
  try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile "$T\r.enc" -TimeoutSec 600 } catch { Fail 'ดาวน์โหลดไม่สำเร็จ ลองวางบรรทัดเดิมอีกครั้ง'; return 1 }
  $ok = $false
  try {
    $a = [Security.Cryptography.Aes]::Create(); $a.Mode = 'CBC'; $a.Padding = 'PKCS7'; $a.Key = Hex $key; $a.IV = Hex $iv
    $in = [IO.File]::OpenRead("$T\r.enc"); $out = [IO.File]::Create("$T\r.tgz")
    $cs = New-Object Security.Cryptography.CryptoStream($in, $a.CreateDecryptor(), 'Read')
    try { $cs.CopyTo($out) } finally { $out.Close(); $cs.Close() }
    $ok = (Get-FileHash -Algorithm SHA256 -LiteralPath "$T\r.tgz").Hash.ToLower() -eq $sha
  } catch {}
  if (-not $ok) { Fail 'รหัสนี้เปิด TadClip รุ่นนี้ไม่ได้ หรือไฟล์ดาวน์โหลดไม่ครบ ลองวางบรรทัดเดิมอีกครั้ง ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE'; return 1 }
  New-Item -ItemType Directory -Path "$T\src" | Out-Null
  # tar.exe opens paths through the ANSI code page: a Thai user name (C:\Users\สมศรี) becomes "?????" (CI 11-12),
  # so run it from inside $T with plain-ASCII relative paths.
  Push-Location -LiteralPath $T; try { & "$env:SystemRoot\System32\tar.exe" -xzf r.tgz -C src } finally { Pop-Location }
  if ($LASTEXITCODE) { Fail 'แตกไฟล์ไม่สำเร็จ ลองวางบรรทัดเดิมอีกครั้ง'; return 1 }
  Set-Content -LiteralPath "$Cfg\code" $code -Encoding ASCII; Set-Content -LiteralPath "$Cfg\until" $until -Encoding ASCII
  Write-Host ([char]0x2713 + " รหัสใช้ได้ถึง $until · code valid until $until")
  $env:TADCLIP_SRC = "$T\src"
  $inst = if ($env:TADCLIP_INSTALLER) { $env:TADCLIP_INSTALLER } else { "$T\src\install.ps1" }
  Get-Content -Raw -Encoding UTF8 -LiteralPath $inst | Invoke-Expression
} finally { Remove-Item -Recurse -Force -LiteralPath $T -ErrorAction SilentlyContinue }
}
