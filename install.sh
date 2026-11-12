#!/usr/bin/env bash
# TadClip install with a paid code (spike: becomes install.sh). Asks for the code sent in LINE, gets this release's key
# (TC1 codes: from the Sheet's checker; TC2 codes: derived on this Mac, no server), downloads the encrypted release,
# checks it, then runs the usual installer on the unpacked copy. Only macOS's own tools: curl, LibreSSL, shasum, tar.
#   curl -fsSL <url>/install.sh | bash          or  TADCLIP_CODE=TC1-... bash install.sh
set -euo pipefail
GATE=${TADCLIP_GATE:-https://script.google.com/macros/s/AKfycbxXamYyB1J4OK5soi3HYRau9bkKvSpzZuVZzevri_w09xKLPhL6OgvE4uG8lznqbOi4/exec}          # the Apps Script web app
META=${TADCLIP_META:-https://raw.githubusercontent.com/npnatt12/tadclip-assets/main/release.json}
INSTALL=${TADCLIP_INSTALLER:-}                                                     # the usual installer (local in tests)
CFG="$HOME/.config/tadclip"; mkdir -p "$CFG"
say() { printf '%s\n' "$*" >&2; }
die() { say ""; say "✗ $1"; exit 1; }
json() { sed -n "s/.*\"$1\": *\"\{0,1\}\([^\",}]*\).*/\1/p" <<<"$2" | head -1; }   # flat JSON we write ourselves

code=${TADCLIP_CODE:-$(cat "$CFG/code" 2>/dev/null || true)}
if [ -z "$code" ]; then
  [ -r /dev/tty ] || die "ไม่มีรหัส TadClip: ใส่รหัสแบบนี้ TADCLIP_CODE=รหัส bash install.sh"
  printf 'วางรหัส TadClip ที่ได้ทาง LINE แล้วกด Enter · paste your TadClip code: ' >/dev/tty; read -r code </dev/tty
fi
code=$(printf '%s' "$code" | tr -d '[:space:]' | tr a-z A-Z)

case "$code" in
  TC1-*)   # the Sheet checks it: revocable, counted
    r=$(curl -fsSL -m 30 -H 'Content-Type: application/json' -d "{\"code\":\"$code\"}" "$GATE" 2>/dev/null) ||
      die "เชื่อมต่อระบบตรวจรหัสไม่ได้ ลองวางบรรทัดเดิมอีกครั้งในอีกสักครู่ (ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE)"
    case "$(json ok "$r")" in
      true) key=$(json key "$r"); iv=$(json iv "$r"); sha=$(json sha256 "$r"); url=$(json url "$r"); until=$(json until "$r");;
      *) case "$(json why "$r")" in
           expired) die "รหัสนี้หมดอายุแล้ว (ใช้ได้ถึง $(json until "$r")) ต่ออายุได้ในกลุ่ม LINE";;
           revoked) die "รหัสนี้ถูกยกเลิกแล้ว ติดต่อทีมในกลุ่ม LINE";;
           *) die "รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่ (คัดลอกทั้งบรรทัด ขึ้นต้นด้วย TC1-)";;
         esac;;
    esac;;
  TC2-*)   # no server: the code holds the key for its last month; earlier months come from hashing it
    E=$(cut -d- -f2 <<<"$code"); raw=$(cut -d- -f3 <<<"$code")
    m=$(curl -fsSL -m 30 "$META" 2>/dev/null) || die "ดาวน์โหลดข้อมูลรุ่นไม่ได้ ลองวางบรรทัดเดิมอีกครั้ง"
    month=$(json month "$m"); iv=$(json iv "$m"); sha=$(json sha256 "$m"); url=$(json url "$m"); until="${E:0:4}-${E:4:2}"
    n=$(( (10#${E:0:4} * 12 + 10#${E:4:2}) - (10#${month:0:4} * 12 + 10#${month:5:2}) ))
    [ "$n" -ge 0 ] || die "รหัสนี้ใช้ได้ถึง ${E:0:4}-${E:4:2} แต่ TadClip รุ่นนี้ออกเดือน $month: ต่ออายุได้ในกลุ่ม LINE"
    k=$(tr A-F a-f <<<"$raw")
    [[ "$k" =~ ^[0-9a-f]{64}$ ]] || die "รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่"
    while [ "$n" -gt 0 ]; do k=$(printf '%s' "$k" | xxd -r -p | shasum -a 256 | cut -c1-64); n=$((n - 1)); done; key=$k;;   # not seq: macOS seq 1 0 counts down
  *) die "รหัสไม่ถูกต้อง ตรวจรหัสที่ได้ทาง LINE แล้วลองใหม่ (ขึ้นต้นด้วย TC1- หรือ TC2-)";;
esac

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
say "ดาวน์โหลด TadClip · downloading TadClip"
curl -fsSL -m 600 -o "$T/r.enc" "$url" || die "ดาวน์โหลดไม่สำเร็จ ลองวางบรรทัดเดิมอีกครั้ง"
/usr/bin/openssl enc -d -aes-256-cbc -K "$key" -iv "$iv" -in "$T/r.enc" -out "$T/r.tgz" 2>/dev/null &&
  [ "$(shasum -a 256 "$T/r.tgz" | cut -c1-64)" = "$sha" ] ||
  die "รหัสนี้เปิด TadClip รุ่นนี้ไม่ได้ หรือไฟล์ดาวน์โหลดไม่ครบ ลองวางบรรทัดเดิมอีกครั้ง ถ้ายังไม่ได้ แจ้งในกลุ่ม LINE"
mkdir "$T/src" && tar -xzf "$T/r.tgz" -C "$T/src"
umask 077; printf '%s\n' "$code" >"$CFG/code"; printf '%s\n' "$until" >"$CFG/until"   # updates re-use it; ready.sh shows "until"
say "✓ รหัสใช้ได้ถึง $until · code valid until $until"
if [ -n "$INSTALL" ]; then TADCLIP_SRC="$T/src" bash "$INSTALL"; else TADCLIP_SRC="$T/src" bash "$T/src/install.sh"; fi
