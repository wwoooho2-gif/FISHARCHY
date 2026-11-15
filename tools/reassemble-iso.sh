#!/bin/bash
# reassemble-iso.sh DIR [OUTPUT]
# Joins fisharchy.iso.part-* from DIR into OUTPUT, checking every part against SHA256SUMS first
# and the joined ISO afterwards. Stops with a clear error on any mismatch.
set -euo pipefail

dir=${1:-.}
out=${2:-fisharchy.iso}

die() { echo "reassemble: $*" >&2; exit 1; }

[[ -d $dir ]] || die "directory not found: $dir"
out=$(realpath -m -- "$out")   # resolve before changing directory
cd -- "$dir"
[[ -f SHA256SUMS ]] || die "SHA256SUMS is missing in $PWD. Download it from the same release as the parts."

mapfile -t parts < <(ls -1 fisharchy.iso.part-* 2>/dev/null | sort)
(( ${#parts[@]} > 0 )) || die "no fisharchy.iso.part-* files in $PWD"

echo "==> Checking ${#parts[@]} part(s) against SHA256SUMS"
for part in "${parts[@]}"; do
  grep -F -- "  $part" SHA256SUMS >/dev/null || die "$part is not listed in SHA256SUMS (wrong release?)"
done
if ! grep -F -- "$(printf '  %s\n' "${parts[@]}")" SHA256SUMS | sha256sum -c --quiet -; then
  die "a part is corrupt or incomplete. Download it again; nothing was joined."
fi

# Every part named in SHA256SUMS must be present, or the ISO would be truncated.
mapfile -t expected < <(awk '$2 ~ /^FISHARCHY\.iso\.part-/ {print $2}' SHA256SUMS | sort)
for name in "${expected[@]}"; do
  [[ -f $name ]] || die "missing part: $name"
done

echo "==> Joining into $out"
cat -- "${parts[@]}" >"$out"

want=$(awk '$2 == "fisharchy.iso" {print $1}' SHA256SUMS)
[[ -n $want ]] || die "SHA256SUMS has no entry for fisharchy.iso"
have=$(sha256sum -- "$out" | cut -d' ' -f1)
if [[ $have != "$want" ]]; then
  rm -f -- "$out"
  die "the joined ISO does not match SHA256SUMS (expected $want, got $have). Removed $out; download the parts again."
fi
echo "OK: $out verified"
