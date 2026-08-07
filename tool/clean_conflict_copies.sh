#!/usr/bin/env bash
# Removes iCloud Drive conflict copies from the working tree.
#
#   ./tool/clean_conflict_copies.sh          # list what would go
#   ./tool/clean_conflict_copies.sh --delete # remove them
#
# This repo lives under ~/Documents, which iCloud syncs. A sync race leaves
# byte-identical duplicates named "foo 2.dart", "foo 3.png" beside the
# original. They are gitignored, but they are not harmless:
#
#   * a duplicate inside lib/ is compiled as real source
#   * android/app/src/main/res/ rejects filenames containing spaces
#   * a stray icon in an Xcode asset catalog can break the build
#
# Only copies byte-identical to their original are removed. Anything that
# differs is reported and left alone — it might be real work.
#
# The actual fix is to move this repo out of the iCloud-synced tree. This
# script is the mitigation, not the cure.

set -euo pipefail
cd "$(dirname "$0")/.."

DELETE=false
[[ "${1:-}" == "--delete" ]] && DELETE=true

found=0; removed=0; kept=0

while IFS= read -r dup; do
  found=$((found + 1))
  original="$(sed -E 's/ [0-9]+(\.[^.]+)$/\1/' <<< "$dup")"

  # No original means this is not a conflict copy at all — "Assignment 2.pdf"
  # matches the same pattern. Nothing to compare against, so nothing to remove.
  if [[ ! -f "$original" ]]; then
    echo "no original, keeping: $dup"
    kept=$((kept + 1))
    continue
  fi

  if ! diff -q "$dup" "$original" >/dev/null 2>&1; then
    echo "DIFFERS, keeping: $dup"
    kept=$((kept + 1))
    continue
  fi

  if $DELETE; then
    rm -f "$dup"
    removed=$((removed + 1))
  else
    echo "would remove: $dup"
  fi
done < <(find . \
  -path ./.git -prune -o \
  -path ./build -prune -o \
  -path ./.dart_tool -prune -o \
  -path ./ios/Pods -prune -o \
  -path ./test_rules/node_modules -prune -o \
  -type f -name "* [0-9].*" -print 2>/dev/null)

echo
if $DELETE; then
  echo "removed $removed of $found ($kept left alone)"
else
  echo "$found found — rerun with --delete to remove ($kept would be kept)"
fi
