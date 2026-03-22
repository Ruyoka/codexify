#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

TARGETS=(
  "${SCRIPT_DIR}/codexify.sh"
  "${SCRIPT_DIR}/setup.sh"
  "${SCRIPT_DIR}/verify.sh"
  "${SCRIPT_DIR}/tests/test_codexify.sh"
)

for target in "${TARGETS[@]}"; do
  printf 'bash -n %s\n' "$target"
  bash -n "$target"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${TARGETS[@]}"
else
  printf 'shellcheck bulunamadi, yalnizca bash -n calisti\n'
fi

printf 'bash %s\n' "${SCRIPT_DIR}/tests/test_codexify.sh"
bash "${SCRIPT_DIR}/tests/test_codexify.sh"
