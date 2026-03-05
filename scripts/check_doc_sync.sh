#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ge 2 ]]; then
  ja_file="$1"
  en_file="$2"
else
  ja_file="JA.md"
  en_file="EN.md"
fi

fail() {
  echo "[doc-sync] ERROR: $1" >&2
  exit 1
}

require_file() {
  local file="$1"
  [[ -f "$file" ]] || fail "Missing file: $file"
}

numbered_h2_sequence() {
  local file="$1"
  sed -nE 's/^[[:space:]]{0,3}##[[:space:]]+([0-9]+)\..*/\1/p' "$file" | paste -sd, -
}

require_file "$ja_file"
require_file "$en_file"

ja_h2_numbers=$(numbered_h2_sequence "$ja_file")
en_h2_numbers=$(numbered_h2_sequence "$en_file")
[[ "$ja_h2_numbers" == "$en_h2_numbers" ]] || fail "Numbered H2 section sequence differs between $ja_file and $en_file"

echo "[doc-sync] OK: $ja_file and $en_file are structurally synchronized"
echo "[doc-sync] numbered-h2-seq match: $ja_h2_numbers"
