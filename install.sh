#!/usr/bin/env bash
# TadClip install with a paid code (spike: becomes install.sh). Asks for the code sent in LINE, gets this release's key
# (TC1 codes: from the Sheet's checker; TC2 codes: derived on this Mac, no server), downloads the encrypted release,
# checks it, then runs the usual installer on the unpacked copy. Only macOS's own tools: curl, LibreSSL, shasum, tar.
#   curl -fsSL <url>/install.sh | bash          or  TADCLIP_CODE=TC1-... bash install.sh
set -euo pipefail
GATE=${TADCLIP_GATE:-https://script.google.com/macros/s/AKfycbxXamYyB1J4OK5soi3HYRau9bkKvSpzZuVZzevri_w09xKLPhL6OgvE4uG8lznqbOi4/exec}          # the Apps Script web app
META=${TADCLIP_META:-https://raw.githubusercontent.com/npnatt12/tadclip-assets/main/release.json}
INSTALL=${TADCLIP_INSTALLER:-}                                                     # the usual installer (local in tests)
CFG="$HOME/.config/tadclip"
say() { printf '%s\n' "$*" >&2; }
die() { say ""; say "✗ $1"; exit 1; }
# Check the target volume before saving credentials or downloading anything.
mac=$(sw_vers -productVersion 2>/dev/null || true)
[ "$(uname -sm)" = "Darwin arm64" ] && [ "${mac%%.*}" -ge 14 ] 2>/dev/null || die "เครื่องนี้ใช้ CraftCut ไม่ได้: ต้องเป็น Mac ชิป Apple (M1 ขึ้นไป) และ macOS 14 ขึ้นไป ยังไม่ได้ใช้รหัส"
D="$HOME/.claude/skills/tadclip"
need=8388608; [ ! -e "$D" ] || need=1048576
free=$(df -k "$HOME" | awk 'NR==2{print $4}')
[ "${free:-0}" -ge "$need" ] || die "พื้นที่ไม่พอ: ต้องว่างประมาณ 8 GB สำหรับติดตั้งครั้งแรก หรือ 1 GB สำหรับอัปเดต ลบไฟล์ที่ไม่ใช้ออก แล้ววางคำสั่งเดิมอีกครั้ง"
json() { sed -n "s/.*\"$1\": *\"\{0,1\}\([^\",}]*\).*/\1/p" <<<"$2" | head -1; }   # flat JSON we write ourselves

code=${TADCLIP_CODE:-$(cat "$CFG/code" 2>/dev/null || true)}
# PDPA (review 11-18): what the check-in sends, shown before the code is given; giving the code accepts it. Shown once more
# to earlier installs (no consent file yet), then recorded with the date
privacy="CraftCut จะส่งข้อมูลการใช้งานไปที่ระบบตรวจรหัสของทีม: ชื่อเครื่อง ระบบ (Mac/Windows) รุ่นโปรแกรม AI ที่ใช้ จำนวนคลิปที่ทำเสร็จ วันที่ทำคลิปแรก และข้อผิดพลาดล่าสุด เพื่อตรวจรหัส แจ้งอัปเดต และดูแลการใช้งาน ไม่ส่งคลิป เสียง หรือข้อความของคุณ · CraftCut sends usage data to our code checker: computer name, Mac/Windows, version, AI used, reels made, first-reel date and the last error, to check your code, offer updates and support you. Never your clips, voice or words."
[ -f "$CFG/consent" ] || { echo; echo "$privacy"; [ -n "$code" ] || echo "วางรหัสแล้วกด Enter = ยอมรับ · pasting your code and pressing Enter accepts this"; echo; }
# Thai digits to 0-9, then keep only A-Z 0-9 and "-": drops spaces, tabs and the zero-width/nbsp characters LINE pastes
clean() { printf '%s' "$1" | LC_ALL=C sed 's/๐/0/g;s/๑/1/g;s/๒/2/g;s/๓/3/g;s/๔/4/g;s/๕/5/g;s/๖/6/g;s/๗/7/g;s/๘/8/g;s/๙/9/g' |
          LC_ALL=C tr -cd 'A-Za-z0-9-' | tr a-z A-Z; }
bad="รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่ (คัดลอกทั้งบรรทัด ขึ้นต้นด้วย TC1-)"
if [ -z "$code" ]; then
  notty="ไม่มีรหัส CraftCut: เปิดแอป Terminal แล้ววางบรรทัดติดตั้งเองอีกครั้ง ระบบจะถามรหัส"   # an agent has no terminal; never paste the code into a chat
  { : </dev/tty; } 2>/dev/null || die "$notty"
  # 25 Nov: the code is not shown while pasting (buyers send screenshots of this window), the rest of a many-line paste
  # is read away so it never runs in Terminal, a code is found anywhere in the line, and it asks up to 3 times
  for try in 1 2 3; do
    printf 'วางรหัส CraftCut ที่ได้ทาง LINE แล้วกด Enter (รหัสจะไม่แสดงบนจอ) · paste your CraftCut code (hidden): ' >/dev/tty
    IFS= read -rs raw </dev/tty || die "$notty"; echo >/dev/tty
    while IFS= read -rs -t 1 _ </dev/tty; do :; done
    if [[ "$(clean "$raw")" =~ (TC1-[A-Z2-7]{13}|TC2-[0-9]{6}-[0-9A-F]{64})(-|$) ]]; then code=${BASH_REMATCH[1]}; break
    elif [[ "$raw" =~ ^[[:space:]]*# || "$raw" == *"curl "* || "$raw" == *install.sh* ]]; then
      echo "ที่วางคือบรรทัดติดตั้ง ไม่ใช่รหัส: เปิด LINE คัดลอกรหัสที่ขึ้นต้นด้วย TC1- หรือ TC2- แล้ววางที่นี่ · that was the install line, not your code" >/dev/tty
    elif [ "$try" -lt 3 ]; then echo "รหัสไม่ถูกต้อง ลองวางใหม่ (ขึ้นต้นด้วย TC1- หรือ TC2-) · not a code, try again ($try/3)" >/dev/tty; fi
  done
  [ -n "$code" ] || die "$bad"
  echo "✓ ได้รหัส ${code:0:4}… แล้ว · code received" >/dev/tty
fi
code=$(clean "$code")

case "$code" in
  TC1-*)   # the Sheet checks it: revocable, counted
    [[ "$code" =~ ^TC1-[A-Z2-7]{13}$ ]] || die "$bad"   # checked here first: a typo never reaches the checker
    # which computer: a random id made once per computer (kept in $CFG) + the computer's own name, for the seller's
    # code list. Nothing else about the computer is sent.
    cid=$(cat "$CFG/install-id" 2>/dev/null || true)
    [[ "$cid" =~ ^[A-Za-z0-9-]{8,64}$ ]] || { cid=$(uuidgen 2>/dev/null || true); [ -z "$cid" ] || (umask 077; mkdir -p "$CFG" && printf '%s\n' "$cid" > "$CFG/install-id"); }
    cname=$(scutil --get ComputerName 2>/dev/null || hostname 2>/dev/null || true)
    cname=$(printf '%s' "$cname" | LC_ALL=C tr -d '\000-\037"\\')   # stays valid JSON; the Sheet keeps it as text
    r=$(curl -fsSL -m 30 -H 'Content-Type: application/json' -d "{\"code\":\"$code\",\"id\":\"$cid\",\"name\":\"$cname\",\"os\":\"mac\"}" "$GATE" 2>/dev/null) ||
      die "เชื่อมต่อระบบตรวจรหัสไม่ได้ ลองวางบรรทัดเดิมอีกครั้งในอีกสักครู่ (ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE)"
    case "$r" in '{'*'"ok"'*) ;;   # Apps Script answers an HTML page when it fails (seen 12-13 Nov): not the buyer's code
      *) die "ระบบตรวจรหัสขัดข้องชั่วคราว ลองวางบรรทัดเดิมอีกครั้งในอีกสักครู่ (ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE)";; esac
    case "$(json ok "$r")" in
      true) key=$(json key "$r"); iv=$(json iv "$r"); sha=$(json sha256 "$r"); url=$(json url "$r"); until=$(json until "$r");;
      *) case "$(json why "$r")" in
           expired) die "รหัสนี้หมดอายุแล้ว (ใช้ได้ถึง $(json until "$r")) ต่ออายุได้ในกลุ่ม LINE";;
           revoked) die "รหัสนี้ถูกยกเลิกแล้ว ติดต่อทีมในกลุ่ม LINE";;
           norelease) die "CraftCut ยังไม่พร้อมให้ติดตั้งตอนนี้ (ทีมกำลังเตรียมรุ่นใหม่) ลองวางบรรทัดเดิมอีกครั้งในอีกสักครู่ ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE";;
           *) die "$bad";;
         esac;;
    esac;;
  TC2-*)   # no server: the code holds the key for its last month; earlier months come from hashing it
    E=$(cut -d- -f2 <<<"$code"); raw=$(cut -d- -f3 <<<"$code")
    m=$(curl -fsSL -m 30 "$META" 2>/dev/null) || die "ดาวน์โหลดข้อมูลรุ่นไม่ได้ ลองวางบรรทัดเดิมอีกครั้ง"
    month=$(json month "$m"); iv=$(json iv "$m"); sha=$(json sha256 "$m"); url=$(json url "$m"); until="${E:0:4}-${E:4:2}"
    n=$(( (10#${E:0:4} * 12 + 10#${E:4:2}) - (10#${month:0:4} * 12 + 10#${month:5:2}) ))
    [ "$n" -ge 0 ] || die "รหัสนี้ใช้ได้ถึง ${E:0:4}-${E:4:2} แต่ CraftCut รุ่นนี้ออกเดือน $month: ต่ออายุได้ในกลุ่ม LINE"
    k=$(tr A-F a-f <<<"$raw")
    [[ "$k" =~ ^[0-9a-f]{64}$ ]] || die "รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่"
    while [ "$n" -gt 0 ]; do k=$(printf '%s' "$k" | xxd -r -p | shasum -a 256 | cut -c1-64); n=$((n - 1)); done; key=$k;;   # not seq: macOS seq 1 0 counts down
  *) die "รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่ (ขึ้นต้นด้วย TC1- หรือ TC2-)";;
esac

# Resolve once above. Fetch checksums from that immutable release, never branch HEAD.
m=$(curl -fsSL -m 30 "${url%/*}/release.json" 2>/dev/null) || die "ดาวน์โหลดข้อมูลรุ่นไม่ได้ ลองวางคำสั่งเดิมอีกครั้ง"
[ "$(json url "$m")" = "$url" ] && [ "$(json sha256 "$m")" = "$sha" ] && [ "$(json iv "$m")" = "$iv" ] || die "ข้อมูลรุ่นไม่ตรงกัน รุ่นเดิมยังอยู่ ลองวางคำสั่งเดิมอีกครั้ง"
encsha=$(json ciphertext_sha256 "$m"); version=$(json version "$m")
[[ "$encsha" =~ ^[0-9a-f]{64}$ ]] && [[ "$version" =~ ^v[0-9][0-9A-Za-z.+-]*$ ]] || die "ข้อมูลตรวจไฟล์ของรุ่นนี้ไม่ครบ รุ่นเดิมยังอยู่ แจ้งทีมในกลุ่ม LINE"
CACHE="$HOME/.cache/tadclip"; cache_made=0; [ -d "$CACHE" ] || cache_made=1; mkdir -p "$CACHE"
enc="$CACHE/$encsha.enc"; part="$CACHE/$encsha.part"
checked() { [ -f "$1" ] && [ "$(shasum -a 256 "$1" | cut -c1-64)" = "$encsha" ]; }
if ! checked "$enc"; then
  rm -f "$enc"
  if ! checked "$part"; then
    say "ดาวน์โหลด CraftCut $version · ดาวน์โหลดที่ค้างจะทำต่อจากเดิม"
    if ! curl -fsSL --connect-timeout 20 --speed-limit 1024 --speed-time 60 -m 600 -C - -o "$part" "$url"; then
      die "ดาวน์โหลดไม่สำเร็จ รุ่นเดิมยังอยู่ วางคำสั่งเดิมอีกครั้งเพื่อดาวน์โหลดต่อ"
    fi
  fi
  checked "$part" || { rm -f "$part"; die "ไฟล์ดาวน์โหลดไม่ครบหรือเปลี่ยนไป รุ่นเดิมยังอยู่ วางคำสั่งเดิมอีกครั้ง"; }
  mv "$part" "$enc"
else
  say "✓ ใช้ไฟล์ $version ที่ตรวจสอบแล้ว ไม่ต้องดาวน์โหลดซ้ำ"
fi

T=$(mktemp -d); cache_rejected=0; stage=""; prior=""; switched=0; success=0
cleanup() {
  rc=$?
  if [ "$switched" = 1 ] && [ "$success" != 1 ]; then
    [ ! -L "$D" ] || rm "$D"
    if [ -n "$prior" ] && { [ -e "$prior" ] || [ -L "$prior" ]; }; then mv "$prior" "$D"; fi
    say "ติดตั้งยังไม่สำเร็จ คืนรุ่นเดิมแล้ว วางคำสั่งเดิมอีกครั้งเพื่อทำต่อ"
  fi
  [ -z "$stage" ] || [ "$success" = 1 ] || rm -rf "$stage"
  rm -rf "$T"
  if [ "$cache_rejected" = 1 ] && [ "$cache_made" = 1 ]; then
    rm -f "$enc" "$part"
    rmdir "$CACHE" "$HOME/.cache" 2>/dev/null || true
  fi
  return "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
/usr/bin/openssl enc -d -aes-256-cbc -K "$key" -iv "$iv" -in "$enc" -out "$T/r.tgz" 2>/dev/null &&
  [ "$(shasum -a 256 "$T/r.tgz" | cut -c1-64)" = "$sha" ] ||
  { cache_rejected=1; die "รหัสนี้เปิด CraftCut รุ่นนี้ไม่ได้ หรือไฟล์ดาวน์โหลดไม่ครบ รุ่นเดิมยังอยู่ แจ้งทีมในกลุ่ม LINE"; }
mkdir "$T/src" && tar -xzf "$T/r.tgz" -C "$T/src"
[ "$(cat "$T/src/.tadclip-version" 2>/dev/null)" = "$version" ] && [ -f "$T/src/.tadclip-paid" ] || die "เวอร์ชันในไฟล์ไม่ตรงกัน รุ่นเดิมยังอยู่ แจ้งทีมในกลุ่ม LINE"

parent=$(dirname "$D"); mkdir -p "$parent"
# A prior kill during the one-time directory-to-link migration can leave the old directory here.
journal="$parent/.tadclip-switch"
if [ -f "$journal" ] && [ ! -e "$D" ] && [ ! -L "$D" ]; then
  recovery=$(cat "$journal")
  case "$recovery" in "$D".previous-*) [ ! -d "$recovery" ] || mv "$recovery" "$D" ;; esac
fi
stage=$(mktemp -d "$parent/.tadclip-$version-XXXXXX")
cp -Rp "$T/src/." "$stage/"
# Personal settings stay opaque. Projects, media and activation live outside this tree.
for state in .env profile.json settings.json config.json; do
  [ ! -e "$D/$state" ] || cp -p "$D/$state" "$stage/$state"
done
# Keep downloaded media while the new payload's files take priority. APFS clones avoid duplicating large caches.
for assets in music sfx emoji; do
  if [ -d "$D/library/$assets" ]; then
    while IFS= read -r -d '' asset; do
      relative=${asset#"$D/library/$assets/"}
      target="$stage/library/$assets/$relative"
      if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        mkdir -p "$(dirname "$target")"
        { cp -cp "$asset" "$target" 2>/dev/null || cp -p "$asset" "$target"; } ||
          die "คัดลอกคลังสื่อไม่สำเร็จ รุ่นเดิมยังอยู่ ตรวจพื้นที่ว่างแล้ววางคำสั่งเดิมอีกครั้ง"
      fi
    done < <(find "$D/library/$assets" -type f -print0)
  fi
done
if [ -e "$D" ] || [ -L "$D" ]; then
  prior="$D.previous-$(date +%s)-$$"
  printf '%s\n' "$prior" > "$journal"
  if [ -L "$D" ]; then ln -s "$(readlink "$D")" "$prior"; else mv "$D" "$prior"; fi
fi
switched=1
# The link is created beside the target: mv then replaces an existing link atomically on macOS.
ln -s "$stage" "$parent/.tadclip-link-$$"
mv -fh "$parent/.tadclip-link-$$" "$D"
rm -f "$journal"
if [ -n "$INSTALL" ]; then TADCLIP_SRC="$T/src" bash "$INSTALL"; else TADCLIP_SRC="$T/src" bash "$D/install.sh"; fi
success=1
mkdir -p "$CFG"
umask 077
[ -f "$CFG/code" ] || printf '%s\n' "$code" > "$CFG/code"
[ -f "$CFG/consent" ] || printf '%s %s\n' "$(date -u +%FT%TZ)" "$privacy" > "$CFG/consent"
[ -f "$CFG/until" ] || printf '%s\n' "$until" > "$CFG/until"
printf '%s\n' "$GATE" > "$CFG/gate"   # the app's check-in (app/hello.mjs) uses the same checker
# the install's stamp (sha256 of the code, not the code) and checker travel with the folder: a copy checks in as a copy
{ printf '%s' "$code" | shasum -a 256 | cut -c1-16 > "$D/.tadclip-stamp" && printf '%s\n' "$GATE" > "$D/.tadclip-gate"; } 2>/dev/null || true
say "✓ ติดตั้ง $version แล้ว · ใช้ได้ตลอด"
[ -z "$prior" ] || say "รุ่นก่อนยังเก็บไว้: $prior"
printf '%s\n' "TADCLIP_INSTALLED=$version"
say "กำลังเช็กความพร้อมก่อนเรียน รอสักครู่ · checking readiness"
if [ ! -f "$D/scripts/ready.sh" ] || ! bash "$D/scripts/ready.sh" --installer; then
  printf '%s\n' "TADCLIP NOT READY · เช็กความพร้อมไม่สำเร็จ ส่งบรรทัดนี้ในกลุ่ม LINE ให้ทีมช่วย · build $version"
fi
