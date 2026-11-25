# TadClip install with a paid code, Windows (spike: becomes install.ps1's first step). Same contract as gate-install.sh:
# TC1 codes are checked by the Sheet's web app, TC2 codes carry their key. Only what Windows 10/11 ships: .NET AES +
# SHA-256, Invoke-RestMethod, tar.exe. Then the usual installer runs on the unpacked copy (TADCLIP_SRC).
#   irm <url>/install.ps1 | iex        or   $env:TADCLIP_CODE='TC1-...'; irm ... | iex
& {
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Gate = if ($env:TADCLIP_GATE) { $env:TADCLIP_GATE } else { 'https://script.google.com/macros/s/AKfycbxXamYyB1J4OK5soi3HYRau9bkKvSpzZuVZzevri_w09xKLPhL6OgvE4uG8lznqbOi4/exec' }
$Meta = if ($env:TADCLIP_META) { $env:TADCLIP_META } else { 'https://raw.githubusercontent.com/npnatt12/tadclip-assets/main/release.json' }
$Cfg = Join-Path $env:APPDATA 'TadClip'
function Fail($m) { $global:LASTEXITCODE = 1; Write-Host ''; Write-Host ([char]0x2717 + ' ' + $m) }   # then 'return 1': exit would close the buyer's window (irm | iex)
function Hex($s) { [byte[]]($s -split '(..)' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }) }

# Target-volume check before saving credentials or downloading anything.
$os = Get-CimInstance Win32_OperatingSystem; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
if ($cpu.Architecture -ne 9 -or [int]$os.BuildNumber -lt 17763) { Fail 'เครื่องนี้ใช้ CraftCut ไม่ได้: ต้องเป็น Windows 10 (1809 ขึ้นไป) หรือ Windows 11 แบบ 64 บิต ชิป Intel หรือ AMD ยังไม่ได้ใช้รหัส'; return 1 }
# Smart App Control (Windows 11) runs only signed programs, and the Python CraftCut sets up isn't signed: 11-18 a ClubGig
# editor's install failed on "An Application Control policy has blocked this file (os error 4551)". Until the install
# works with it on, say so in Thai before downloading anything. 1 = on (blocks); 2 = evaluation (watches, may switch on).
$sac = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
# $env:CUTCRAFT_SAC='try': install anyway (Python is now python.org's signed build), to test on a PC with it on; if
# Windows blocks something, Blocked lists the files so the team knows which tool to replace
function Blocked { if ($sac -ne 1) { return }; try {
  Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-CodeIntegrity/Operational'; Id = 3033, 3077; StartTime = $started } -MaxEvents 20 -ErrorAction Stop |
    ForEach-Object { $_.Properties[1].Value } | Select-Object -Unique -First 8 |   # 3033/3077: [1] = the blocked file
    ForEach-Object { Write-Host "Smart App Control บล็อก · blocked: $_" } } catch {} }
$started = Get-Date
if ($sac -eq 1 -and $env:CUTCRAFT_SAC -eq 'try') { Write-Host 'ทดสอบติดตั้งทั้งที่เปิด Smart App Control · testing with Smart App Control on' }
elseif ($sac -eq 1) { Fail 'Windows เครื่องนี้เปิด Smart App Control อยู่ ซึ่งจะบล็อกเครื่องมือที่ CraftCut ใช้ ตอนนี้จึงยังติดตั้งไม่ได้ ทีมกำลังแก้ให้ใช้ได้โดยไม่ต้องปิด ถ้าต้องการใช้ตอนนี้: Windows Security > App & browser control > Smart App Control > Off แล้ววางบรรทัดเดิมอีกครั้ง (ปิดแล้ว Windows จะไม่บล็อกโปรแกรมที่ไม่มีลายเซ็น) · Smart App Control is on and blocks the tools CraftCut installs'; return 1 }
if ($sac -eq 2) { Write-Host 'หมายเหตุ: Smart App Control กำลังประเมินเครื่องนี้ ถ้ามันเปิดเองภายหลัง CraftCut อาจถูกบล็อก · note: Smart App Control is evaluating this PC' }
$D = Join-Path $HOME '.claude\skills\tadclip'
$drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($HOME))
$need = if (Test-Path -LiteralPath $D) { 1GB } else { 8GB }
# Data drive (11-18: a ClubGig editor's C: had 7 GB free, D: had room). The heavy parts (Python tools, speech model, caches,
# the clips folder) can live on another drive, joined back with junctions so every path stays the same. Asked once, only
# when C: is short and another drive has room; kept in %APPDATA%\TadClip\data for updates. TADCLIP_DATA preselects it.
$data = $env:TADCLIP_DATA
if (-not $data -and (Test-Path -LiteralPath "$Cfg\data")) { $data = (Get-Content -LiteralPath "$Cfg\data" -Raw).Trim() }
if (-not $data -and $drive.AvailableFreeSpace -lt $need) {
  $other = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady -and $_.Name -ne $drive.Name -and $_.AvailableFreeSpace -ge 8GB })
  if ($other.Count) {
    Write-Host ''
    Write-Host ('ไดรฟ์ {0} ว่าง {1} GB ไม่พอ (ต้องประมาณ 8 GB) · ติดตั้งส่วนใหญ่ไว้ที่ไดรฟ์อื่นได้: {2}' -f $drive.Name.Substring(0, 1), [math]::Floor($drive.AvailableFreeSpace / 1GB), (($other | ForEach-Object { '{0} (ว่าง {1} GB)' -f $_.Name.Substring(0, 1), [math]::Floor($_.AvailableFreeSpace / 1GB) }) -join ', '))
    $pick = try { Read-Host 'พิมพ์ตัวอักษรไดรฟ์ เช่น D แล้วกด Enter (กด Enter เฉยๆ = ยกเลิก) · type a drive letter' } catch { '' }
    $pick = "$pick".Trim().TrimEnd(':').ToUpper()
    if ($pick -and ($other | Where-Object { $_.Name.Substring(0, 1) -eq $pick })) { $data = $pick + ':\CutCraft' }
  }
}
if ($data) {
  $dataDrive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($data))
  if ($drive.AvailableFreeSpace -lt 1GB -or $dataDrive.AvailableFreeSpace -lt $need) { Fail ('พื้นที่ไม่พอ: ไดรฟ์ {0} ต้องว่างอย่างน้อย 1 GB และ {1} ต้องว่างประมาณ 8 GB ลบไฟล์ที่ไม่ใช้ออก แล้ววางคำสั่งเดิมอีกครั้ง' -f $drive.Name.Substring(0, 1), $data); return 1 }
  $env:TADCLIP_DATA = $data   # the inner installer and setup.sh measure this drive
  Write-Host "ไฟล์ใหญ่ (เครื่องมือ โมเดลเสียง คลิป) จะอยู่ที่ $data · heavy files go to $data"
} elseif ($drive.AvailableFreeSpace -lt $need) { Fail 'พื้นที่ไม่พอ: ต้องว่างประมาณ 8 GB สำหรับติดตั้งครั้งแรก หรือ 1 GB สำหรับอัปเดต ลบไฟล์ที่ไม่ใช้ออก แล้ววางคำสั่งเดิมอีกครั้ง'; return 1 }
# each heavy folder becomes a junction into the data folder; what is already there moves with it (robocopy /MOVE)
function Link-Data($data) {
  $links = [ordered]@{ 'venvs' = "$HOME\.venvs"; 'tools' = "$HOME\.local\share\tadclip-tools"; 'huggingface' = "$HOME\.cache\huggingface"
    'hyperframes' = "$HOME\.cache\hyperframes"; 'uv-local' = (Join-Path $env:LOCALAPPDATA 'uv'); 'uv-roaming' = (Join-Path $env:APPDATA 'uv'); 'TadClip' = "$HOME\TadClip" }
  foreach ($k in $links.Keys) {
    $link = $links[$k]; $target = Join-Path $data $k
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction') { continue }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    if ($item) {
      & robocopy $link $target /E /MOVE /NFL /NDL /NJH /NJS /NP | Out-Null
      if ($LASTEXITCODE -ge 8) { throw "moving $link to $target failed (robocopy $LASTEXITCODE)" }
      if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Recurse -Force }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $link) | Out-Null
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
  }
}
function Hash($p) { if (-not (Test-Path -LiteralPath $p)) { return '' }; $s = [IO.File]::OpenRead($p); try { -join ([Security.Cryptography.SHA256]::Create().ComputeHash($s) | ForEach-Object { $_.ToString('x2') }) } finally { $s.Dispose() } }
$code = $env:TADCLIP_CODE
if (-not $code -and (Test-Path -LiteralPath "$Cfg\code")) { $code = (Get-Content -LiteralPath "$Cfg\code" -Raw) }
# PDPA (review 11-18): what the check-in sends, shown before the code is given; giving the code accepts it
$privacy = 'CraftCut จะส่งข้อมูลการใช้งานไปที่ระบบตรวจรหัสของทีม: ชื่อเครื่อง ระบบ (Mac/Windows) รุ่นโปรแกรม AI ที่ใช้ จำนวนคลิปที่ทำเสร็จ วันที่ทำคลิปแรก และข้อผิดพลาดล่าสุด เพื่อตรวจรหัส แจ้งอัปเดต และดูแลการใช้งาน ไม่ส่งคลิป เสียง หรือข้อความของคุณ · CraftCut sends usage data to our code checker: computer name, Mac/Windows, version, AI used, reels made, first-reel date and the last error, to check your code, offer updates and support you. Never your clips, voice or words.'
if (-not (Test-Path -LiteralPath "$Cfg\consent")) { Write-Host ''; Write-Host $privacy; if (-not $code) { Write-Host 'วางรหัสแล้วกด Enter = ยอมรับ · pasting your code and pressing Enter accepts this' }; Write-Host '' }
# Thai digits to 0-9, then keep only A-Z 0-9 and "-": drops spaces and the zero-width/nbsp characters LINE pastes
function Clean($s) { (-join ("$s".ToCharArray() | ForEach-Object { if ($_ -ge [char]0x0E50 -and $_ -le [char]0x0E59) { [char](48 + [int]$_ - 0x0E50) } else { $_ } }) -replace '[^A-Za-z0-9-]', '').ToUpper() }
$bad = 'รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่ (คัดลอกทั้งบรรทัด ขึ้นต้นด้วย TC1-)'
if (-not $code) {   # an agent has no console to ask in; never paste the code into a chat
  # 11-25: a Windows tester pasted the installer script itself at this prompt. Read-Host took its first line (a comment)
  # and failed, and the other ~200 lines ran at the PowerShell prompt. Now: drop the rest of a many-line paste, find a
  # code anywhere in the line ("รหัส: TC1-..."), and ask again (3 tries) instead of stopping.
  for ($try = 1; $try -le 3 -and -not $code; $try++) {
    # hidden (25 Nov): buyers send screenshots of this window. piped input (CI) is read plainly
    $ask = 'วางรหัส CraftCut ที่ได้ทาง LINE แล้วกด Enter (รหัสจะไม่แสดงบนจอ) · paste your CraftCut code (hidden)'
    try {   # -AsSecureString waits forever on piped input (CI): hide only in a real console
      if ([Console]::IsInputRedirected) { $raw = Read-Host $ask }
      else { $s = Read-Host $ask -AsSecureString; $raw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)) }
    } catch { Fail 'ไม่มีรหัส CraftCut: เปิด PowerShell แล้ววางบรรทัดติดตั้งเองอีกครั้ง ระบบจะถามรหัส'; return 1 }
    if ($null -eq $raw) { break }   # no more input (redirected stdin ran out)
    Start-Sleep -Milliseconds 300   # a long paste arrives in pieces
    try { $Host.UI.RawUI.FlushInputBuffer() } catch {}   # no console (ISE, CI): nothing to flush
    $c = Clean $raw
    if ($c -cmatch 'TC1-[A-Z2-7]{13}(?![A-Z0-9])' -or $c -cmatch 'TC2-\d{6}-[0-9A-F]{64}(?![A-Z0-9])') { $code = $Matches[0] }
    elseif ("$raw" -match 'irm |iex|install\.ps1|^\s*#') { Write-Host 'ที่วางคือบรรทัดติดตั้ง ไม่ใช่รหัส: เปิด LINE คัดลอกรหัสที่ขึ้นต้นด้วย TC1- หรือ TC2- แล้ววางที่นี่ · that was the install line, not your code' }
    elseif ($try -lt 3) { Write-Host ('รหัสไม่ถูกต้อง ลองวางใหม่ (ขึ้นต้นด้วย TC1- หรือ TC2-) · not a code, try again ({0}/3)' -f $try) }
  }
  if (-not $code) { Fail $bad; return 1 }
  Write-Host ('{0} ได้รหัส {1}… แล้ว · code received' -f [char]0x2713, $code.Substring(0, 4))
}
$code = Clean $code

if ($code -like 'TC1-*') {
  if ($code -cnotmatch '^TC1-[A-Z2-7]{13}$') { Fail $bad; return 1 }   # a typo never reaches the checker
  # which computer: a random id made once per computer (kept in $Cfg) + the computer's own name, for the seller's code list
  $idFile = Join-Path $Cfg 'install-id'; $cid = ''
  if (Test-Path -LiteralPath $idFile) { $cid = "$(Get-Content -LiteralPath $idFile -Raw)".Trim() }
  if ($cid -notmatch '^[A-Za-z0-9-]{8,64}$') { $cid = [guid]::NewGuid().ToString(); try { New-Item -ItemType Directory -Force -Path $Cfg | Out-Null; Set-Content -LiteralPath $idFile -Value $cid -Encoding ascii } catch {} }
  $body = @{ code = $code; id = $cid; name = "$env:COMPUTERNAME"; os = 'windows' } | ConvertTo-Json -Compress
  try { $r = Invoke-RestMethod -Method Post -Uri $Gate -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 }
  catch { Fail 'เชื่อมต่อระบบตรวจรหัสไม่ได้ ลองวางบรรทัดเดิมอีกครั้งในอีกสักครู่ (ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE)'; return 1 }
  # Apps Script answers an HTML page when it fails (seen 12-13 Nov): Invoke-RestMethod hands that back as a string
  if ($null -eq $r -or $r -is [string] -or $null -eq $r.ok) { Fail 'ระบบตรวจรหัสขัดข้องชั่วคราว ลองวางบรรทัดเดิมอีกครั้งในอีกสักครู่ (ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE)'; return 1 }
  if (-not $r.ok) {
    switch ($r.why) {
      'expired' { Fail "รหัสนี้หมดอายุแล้ว (ใช้ได้ถึง $($r.until)) ต่ออายุได้ในกลุ่ม LINE"; return 1 }
      'revoked' { Fail 'รหัสนี้ถูกยกเลิกแล้ว ติดต่อทีมในกลุ่ม LINE'; return 1 }
      'norelease' { Fail 'CraftCut ยังไม่พร้อมให้ติดตั้งตอนนี้ (ทีมกำลังเตรียมรุ่นใหม่) ลองวางบรรทัดเดิมอีกครั้งในอีกสักครู่ ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE'; return 1 }
      default   { Fail $bad; return 1 }
    }
  }
  $key = $r.key; $iv = $r.iv; $sha = $r.sha256; $url = $r.url; $until = $r.until
} elseif ($code -match '^TC2-(\d{4})(\d{2})-([0-9A-F]{64})$') {
  $E = [int]$Matches[1] * 12 + [int]$Matches[2]; $until = "$($Matches[1])-$($Matches[2])"; $k = Hex $Matches[3].ToLower()
  try { $m = Invoke-RestMethod -Uri $Meta -TimeoutSec 30 } catch { Fail 'ดาวน์โหลดข้อมูลรุ่นไม่ได้ ลองวางบรรทัดเดิมอีกครั้ง'; return 1 }
  $n = $E - ([int]$m.month.Substring(0, 4) * 12 + [int]$m.month.Substring(5, 2))
  if ($n -lt 0) { Fail "รหัสนี้ใช้ได้ถึง $until แต่ CraftCut รุ่นนี้ออกเดือน $($m.month): ต่ออายุได้ในกลุ่ม LINE"; return 1 }
  $h = [Security.Cryptography.SHA256]::Create(); for ($i = 0; $i -lt $n; $i++) { $k = $h.ComputeHash($k) }
  $key = -join ($k | ForEach-Object { $_.ToString('x2') }); $iv = $m.iv; $sha = $m.sha256; $url = $m.url
} else { Fail 'รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่ (ขึ้นต้นด้วย TC1- หรือ TC2-)'; return 1 }

# Metadata is pinned to the release returned above; no newest-prerelease or branch lookup.
try { $m = Invoke-RestMethod -Uri ($url.Substring(0, $url.LastIndexOf('/')) + '/release.json') -TimeoutSec 30 }
catch { Fail 'ดาวน์โหลดข้อมูลรุ่นไม่ได้ ลองวางคำสั่งเดิมอีกครั้ง'; return 1 }
if ($m.url -ne $url -or $m.sha256 -ne $sha -or $m.iv -ne $iv -or $m.ciphertext_sha256 -notmatch '^[0-9a-f]{64}$' -or $m.version -notmatch '^v[0-9][0-9A-Za-z.+-]*$') { Fail 'ข้อมูลรุ่นไม่ตรงกัน รุ่นเดิมยังอยู่ แจ้งทีมในกลุ่ม LINE'; return 1 }
$version = $m.version; $encsha = $m.ciphertext_sha256
$Cache = Join-Path $env:LOCALAPPDATA 'TadClip\cache'; $cacheMade = -not (Test-Path -LiteralPath $Cache); New-Item -ItemType Directory -Force -Path $Cache | Out-Null
$enc = Join-Path $Cache ($encsha + '.enc'); $part = Join-Path $Cache ($encsha + '.part')
if ((Hash $enc) -ne $encsha) {
  Remove-Item -LiteralPath $enc -ErrorAction SilentlyContinue
  if ((Hash $part) -ne $encsha) {
    Write-Host "ดาวน์โหลด CraftCut $version · ดาวน์โหลดที่ค้างจะทำต่อจากเดิม"
    $start = if (Test-Path -LiteralPath $part) { (Get-Item -LiteralPath $part).Length } else { 0 }
    $response = $null; $output = $null
    try {
      $request = [Net.HttpWebRequest]::Create($url); $request.Timeout = 600000; $request.ReadWriteTimeout = 60000
      if ($start -gt 0) { $request.AddRange([long]$start) }
      $response = $request.GetResponse()
      if ($start -gt 0 -and [int]$response.StatusCode -ne 206) { $start = 0 }
      if ($start -gt 0 -and $response.Headers['Content-Range'] -notmatch ('^bytes ' + $start + '-')) { throw 'range mismatch' }
      $mode = if ($start -gt 0) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
      $output = [IO.File]::Open($part, $mode, [IO.FileAccess]::Write)
      $response.GetResponseStream().CopyTo($output)
    } catch { Fail 'ดาวน์โหลดไม่สำเร็จ รุ่นเดิมยังอยู่ วางคำสั่งเดิมอีกครั้งเพื่อดาวน์โหลดต่อ'; return 1 }
    finally { if ($output) { $output.Dispose() }; if ($response) { $response.Close() } }
  }
  if ((Hash $part) -ne $encsha) { Remove-Item -LiteralPath $part -ErrorAction SilentlyContinue; Fail 'ไฟล์ดาวน์โหลดไม่ครบหรือเปลี่ยนไป รุ่นเดิมยังอยู่ วางคำสั่งเดิมอีกครั้ง'; return 1 }
  Move-Item -LiteralPath $part -Destination $enc -Force
} else { Write-Host "ใช้ไฟล์ $version ที่ตรวจสอบแล้ว ไม่ต้องดาวน์โหลดซ้ำ" }

$T = Join-Path $env:TEMP ('tadclip-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $T | Out-Null
$cacheRejected = $false; $stage = $null; $prior = $null; $switched = $false; $success = $false
try {
  $ok = $false
  try {
    $a = [Security.Cryptography.Aes]::Create(); $a.Mode = 'CBC'; $a.Padding = 'PKCS7'; $a.Key = Hex $key; $a.IV = Hex $iv
    $cipherFile = [IO.File]::OpenRead($enc); $output = [IO.File]::Create("$T\r.tgz")
    $cs = New-Object Security.Cryptography.CryptoStream($cipherFile, $a.CreateDecryptor(), 'Read')
    try { $cs.CopyTo($output) } finally { $output.Dispose(); $cs.Dispose(); $a.Dispose() }
    $ok = (Hash "$T\r.tgz") -eq $sha
  } catch {}
  if (-not $ok) { $cacheRejected = $true; Fail 'รหัสนี้เปิด CraftCut รุ่นนี้ไม่ได้ หรือไฟล์ดาวน์โหลดไม่ครบ รุ่นเดิมยังอยู่ แจ้งทีมในกลุ่ม LINE'; return 1 }
  New-Item -ItemType Directory -Path "$T\src" | Out-Null
  Push-Location -LiteralPath $T; try { & "$env:SystemRoot\System32\tar.exe" -xzf r.tgz -C src --exclude '._*' --exclude '*/._*' } finally { Pop-Location }
  # ._* = macOS metadata a Mac-built archive can carry; '._.' can't be copied on Windows (11-18: every paid Windows install failed on it)
  if ($LASTEXITCODE) { Fail 'แตกไฟล์ไม่สำเร็จ รุ่นเดิมยังอยู่ ลองวางคำสั่งเดิมอีกครั้ง'; return 1 }
  if ((Get-Content -LiteralPath "$T\src\.tadclip-version" -Raw).Trim() -ne $version -or -not (Test-Path -LiteralPath "$T\src\.tadclip-paid")) { Fail 'เวอร์ชันในไฟล์ไม่ตรงกัน รุ่นเดิมยังอยู่ แจ้งทีมในกลุ่ม LINE'; return 1 }
  $parent = Split-Path -Parent $D; New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $journal = Join-Path $parent '.tadclip-switch'
  if ((Test-Path -LiteralPath $journal) -and -not (Test-Path -LiteralPath $D)) {
    $recovery = (Get-Content -LiteralPath $journal -Raw).Trim()
    if ($recovery.StartsWith($D + '.previous-') -and (Test-Path -LiteralPath $recovery)) { [IO.Directory]::Move($recovery, $D) }
  }
  $stage = Join-Path $parent ('.tadclip-stage-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stage | Out-Null
  Get-ChildItem -Force -LiteralPath "$T\src" | Copy-Item -Destination $stage -Recurse -Force
  foreach ($state in @('.env','profile.json','settings.json','config.json')) {
    $old = Join-Path $D $state
    if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination (Join-Path $stage $state) -Force }
  }
  # Preserve downloaded media; files supplied by the new payload take priority.
  foreach ($assets in @('music','sfx','emoji')) {
    $oldAssets = Join-Path $D ('library\' + $assets)
    if (Test-Path -LiteralPath $oldAssets) {
      foreach ($file in Get-ChildItem -LiteralPath $oldAssets -Recurse -File -Force) {
        $relative = $file.FullName.Substring($oldAssets.Length + 1)
        $target = Join-Path (Join-Path $stage ('library\' + $assets)) $relative
        if (-not (Test-Path -LiteralPath $target)) {
          New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
          Copy-Item -LiteralPath $file.FullName -Destination $target
        }
      }
    }
  }
  if (Test-Path -LiteralPath $D) {
    $prior = $D + '.previous-' + [guid]::NewGuid().ToString('N')
    Set-Content -LiteralPath $journal -Value $prior -Encoding UTF8
    [IO.Directory]::Move($D, $prior)
  }
  $switched = $true
  [IO.Directory]::Move($stage, $D)
  Remove-Item -LiteralPath $journal -ErrorAction SilentlyContinue
  $env:TADCLIP_SRC = "$T\src"
  if ($env:TADCLIP_DATA) { Link-Data $env:TADCLIP_DATA }
  $inst = if ($env:TADCLIP_INSTALLER) { $env:TADCLIP_INSTALLER } else { Join-Path $D 'install.ps1' }
  $global:LASTEXITCODE = 0
  $result = @(Get-Content -Raw -Encoding UTF8 -LiteralPath $inst | Invoke-Expression)
  $rc = $global:LASTEXITCODE
  if ($result.Count -and $result[-1] -is [int]) { $rc = $result[-1] }
  if ($rc) { Fail 'ติดตั้งยังไม่สำเร็จ คืนรุ่นเดิมแล้ว วางคำสั่งเดิมอีกครั้งเพื่อทำต่อ'; Blocked; return 1 }
  $success = $true
  New-Item -ItemType Directory -Force -Path $Cfg | Out-Null
  if (-not (Test-Path -LiteralPath "$Cfg\code")) { Set-Content -LiteralPath "$Cfg\code" $code -Encoding ASCII }
  if (-not (Test-Path -LiteralPath "$Cfg\consent")) { Set-Content -LiteralPath "$Cfg\consent" ((Get-Date).ToUniversalTime().ToString('s') + 'Z ' + $privacy) -Encoding UTF8 }
  if (-not (Test-Path -LiteralPath "$Cfg\until")) { Set-Content -LiteralPath "$Cfg\until" $until -Encoding ASCII }
  Set-Content -LiteralPath "$Cfg\gate" $Gate -Encoding ASCII
  if ($env:TADCLIP_DATA) { Set-Content -LiteralPath "$Cfg\data" $env:TADCLIP_DATA -Encoding ASCII }   # the app's check-in (app/hello.mjs) uses the same checker
  try {   # the install's stamp (sha256 of the code, not the code) and checker travel with the folder: a copy checks in as a copy
    $h = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($code))
    Set-Content -LiteralPath "$D\.tadclip-stamp" (-join ($h[0..7] | ForEach-Object { $_.ToString('x2') })) -Encoding ASCII
    Set-Content -LiteralPath "$D\.tadclip-gate" $Gate -Encoding ASCII
  } catch {}
  $global:LASTEXITCODE = 0
  Write-Host "ติดตั้ง $version แล้ว · ใช้ได้ตลอด"
  if ($prior) { Write-Host "รุ่นก่อนยังเก็บไว้: $prior" }
  Write-Host "TADCLIP_INSTALLED=$version"
  Write-Host 'กำลังเช็กความพร้อมก่อนเรียน รอสักครู่ · checking readiness'
  try {
    $bash = $env:CLAUDE_CODE_GIT_BASH_PATH
    if (-not $bash) { $bash = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User') }
    $ready = Join-Path $D 'scripts\ready.sh'
    if (-not $bash -or -not (Test-Path -LiteralPath $bash) -or -not (Test-Path -LiteralPath $ready)) { throw 'readiness unavailable' }
    & $bash --noprofile --norc ($ready -replace '\\', '/') --installer | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'readiness incomplete' }
  } catch {
    Write-Host "TADCLIP NOT READY · เช็กความพร้อมไม่สำเร็จ ส่งบรรทัดนี้ในกลุ่ม LINE ให้ทีมช่วย · build $version"
    Blocked
  }
  $global:LASTEXITCODE = 0
} catch {
  # 11-18: a ClubGig editor's install stopped here with only this line, and the cause was lost. Show it and keep it.
  $why = ("$($_.Exception.Message)" -replace '\s+', ' ').Trim(); $at = $_.InvocationInfo.ScriptLineNumber
  Fail 'ติดตั้งไม่สำเร็จ รุ่นเดิมยังอยู่ วางคำสั่งเดิมอีกครั้งเพื่อทำต่อ'
  Write-Host "สาเหตุ · reason: $why (line $at)"
  Blocked
  if ($why -match 'being used by another process|Access to the path .* is denied|ใช้งานอยู่') {
    Write-Host 'ปิดหน้าต่าง CraftCut และ File Explorer / PowerShell ที่เปิดโฟลเดอร์ tadclip อยู่ แล้ววางคำสั่งเดิมอีกครั้ง · close CraftCut and any window open in the tadclip folder, then paste the line again'
  }
  try {
    $logs = Join-Path $env:LOCALAPPDATA 'TadClip\Logs'; New-Item -ItemType Directory -Force -Path $logs | Out-Null
    Add-Content -LiteralPath (Join-Path $logs 'gate-install.log') -Encoding UTF8 -Value ("{0:yyyy-MM-dd HH:mm:ss} {1} failed at line {2}: {3}" -f (Get-Date), $version, $at, $why)
  } catch {}
  return 1
}
finally {
  if ($switched -and -not $success) {
    if (Test-Path -LiteralPath $D) { [IO.Directory]::Move($D, $D + '.failed-' + [guid]::NewGuid().ToString('N')) }
    if ($prior -and (Test-Path -LiteralPath $prior)) { [IO.Directory]::Move($prior, $D) }
  }
  if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -Recurse -Force -LiteralPath $stage -ErrorAction SilentlyContinue }
  Remove-Item -Recurse -Force -LiteralPath $T -ErrorAction SilentlyContinue
  if ($cacheRejected -and $cacheMade) {
    Remove-Item -LiteralPath $enc -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $part -ErrorAction SilentlyContinue
    try { [IO.Directory]::Delete($Cache); [IO.Directory]::Delete((Split-Path -Parent $Cache)) } catch {}
  }
}
}
