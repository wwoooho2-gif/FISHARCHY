#!/bin/bash

set -euo pipefail

dir=${1:-.}
out=${2:-FISHARCHY.iso}

cd -- "$dir"

mapfile -t parts < <(ls -1 FISHARCHY.iso.part-* 2>/dev/null | sort)
if (( ${#parts[@]} == 0 )); then
  echo "reassemble: no FISHARCHY.iso.part-* files in $PWD" >&2
  exit 1
fi

cat -- "${parts[@]}" >"$out"
if [[ -f FISHARCHY.iso.sha256 ]]; then
  sha256sum -c FISHARCHY.iso.sha256
fi
echo "Wrote $PWD/$out"
