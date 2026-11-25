#!/bin/bash
# The live files, checked the way buyers' computers read them (26 Nov). Run by go-live before anything goes live, and by
# verify-live on every push to main: rc3.15 and rc3.16 went live by hand-pushed commits after go-live had refused them
# (only the .enc was attached), and every install broke for 12 hours.
#   bash .github/verify.sh <dir with release.json install.sh install.ps1 README.md> [--public]
# --public: also fetch release.json from the release's own download folder (what both installers do) and compare.
set -uo pipefail
D=${1:?dir}; bad=0; R=${GITHUB_REPOSITORY:-npnatt12/tadclip-assets}; T=${RUNNER_TEMP:-$(mktemp -d)}
ok() { echo "✓ $*"; }; no() { echo "✗ $*"; bad=1; }
url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$D/release.json") || { echo "✗ release.json unreadable"; exit 1; }
tag=$(basename "$(dirname "$url")"); enc=$(basename "$url")
have=$(gh release view "$tag" -R "$R" --json assets,isDraft --jq 'if .isDraft then "DRAFT" else .assets[].name end') || { echo "✗ no release $tag"; exit 1; }
[ "$have" = DRAFT ] && no "$tag is still a draft: buyers can't download it"
for f in release.json install.sh install.ps1 README.md "$enc"; do grep -qx "$f" <<<"$have" && ok "$tag has $f" || no "$tag is missing $f"; done
for f in install.sh install.ps1; do
  [ "$(head -c3 "$D/$f" | od -An -tx1 | tr -d ' ')" = efbbbf ] && no "$f starts with a BOM (irm | iex fails on line 1)" || ok "$f: no BOM"
  grep -q REPLACE_ME "$D/$f" && no "$f still has REPLACE_ME" || ok "$f: checker address filled in"
done
bash -n "$D/install.sh" && ok "install.sh parses (bash)" || no "install.sh doesn't parse"
# as irm hands it to iex: the bytes as UTF-8, a BOM kept as U+FEFF
if ! command -v pwsh >/dev/null; then echo "- install.ps1 parse: skipped (no pwsh here; CI has it)"
elif pwsh -NoProfile -Command '$t = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($args[0])); $e = $null; [void][Management.Automation.Language.Parser]::ParseInput($t, [ref]$null, [ref]$e); if ($e.Count) { $e | Select-Object -First 3 | ForEach-Object { "  " + $_.Message }; exit 1 }' "$D/install.ps1"
then ok "install.ps1 parses as irm | iex reads it"; else no "install.ps1 doesn't parse as irm | iex reads it"; fi
if [ "${2:-}" = --public ]; then   # GitHub's download CDN may answer 404 for a few minutes after an upload
  for i in $(seq 1 12); do curl -fsSL -m 30 "${url%/*}/release.json?v=$i$RANDOM" -o "$T/pub.json" 2>/dev/null && break; sleep 15; done
  cmp -s "$T/pub.json" "$D/release.json" && ok "the public ${url%/*}/release.json is this one" || no "the public release.json (what installers fetch) is missing or different"
fi
[ $bad = 0 ] && echo "OK: $tag" || { echo "FAIL: installs would break"; exit 1; }
