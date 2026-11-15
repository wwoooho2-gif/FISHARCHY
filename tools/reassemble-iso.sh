#!/bin/bash
# reassemble-iso.sh - join FISHARCHY.iso.part-* into one ISO, verified.
#
#   ./reassemble-iso.sh [directory-with-parts] [output-file]
#
# Needs SHA256SUMS (from the same release) next to the parts. Every part is
# checked BEFORE joining and the finished ISO AFTERWARDS; any mismatch stops
# with an error and no ISO is left behind.

set -euo pipefail

die() { echo "reassemble: $*" >&2; exit 1; }

dir=${1:-.}
out=${2:-FISHARCHY.iso}
# Resolve the output path against where the user ran the command, not $dir.
case $out in
  /*) ;;
  *) out=$PWD/$out ;;
esac

cd -- "$dir" || die "cannot enter $dir"
[[ -f SHA256SUMS ]] ||
  die "SHA256SUMS not found in $PWD; download it from the same release as the parts"

mapfile -t parts < <(ls -1 FISHARCHY.iso.part-* 2>/dev/null | sort)
(( ${#parts[@]} > 0 )) || die "no FISHARCHY.iso.part-* files in $PWD"

echo "==> Checking ${#parts[@]} part(s) against SHA256SUMS"
grep -E '[ *]FISHARCHY\.iso\.part-' SHA256SUMS >.parts.sums.$$ ||
  die "SHA256SUMS lists no FISHARCHY.iso.part-* files"
trap 'rm -f .parts.sums.$$ "$out.partial"' EXIT
sha256sum -c .parts.sums.$$ ||
  die "a part is missing or corrupt (see above). Download it again; nothing was joined."

# Every listed part must be present; sha256sum -c already fails on a missing one.
echo "==> Joining"
cat -- "${parts[@]}" >"$out.partial"

want=$(awk '$2 == "FISHARCHY.iso" || $2 == "*FISHARCHY.iso" {print $1}' SHA256SUMS)
[[ -n $want ]] || die "SHA256SUMS has no entry for FISHARCHY.iso"
got=$(sha256sum "$out.partial" | cut -d' ' -f1)
if [[ $got != "$want" ]]; then
  die "the joined ISO does not match SHA256SUMS (expected $want, got $got); not keeping it"
fi

mv -- "$out.partial" "$out"
echo "OK: wrote $out and verified it against SHA256SUMS"
