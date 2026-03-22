#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

APT_PACKAGES=(
  bash
  coreutils
  findutils
  gawk
  git
  grep
  procps
  ripgrep
  sed
  tmux
)

note() {
  printf '%s\n' "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_with_apt() {
  if ! have_cmd apt-get; then
    note "apt-get yok. Paket kurulumu atlandi."
    return 0
  fi

  note "APT paketleri kuruluyor..."
  sudo apt-get update
  sudo apt-get install -y "${APT_PACKAGES[@]}"
}

verify_codex_cli() {
  if have_cmd codex; then
    note "codex CLI bulundu: $(command -v codex)"
    return 0
  fi

  note "codex CLI bulunamadi."
  note "OpenAI Codex CLI'yi kurup PATH icine ekleyin, sonra scripti tekrar calistirin."
  return 1
}

main() {
  note "Kurulum basladi: ${SCRIPT_DIR}"
  install_with_apt
  verify_codex_cli
  chmod +x "${SCRIPT_DIR}/codexify.sh" "${SCRIPT_DIR}/setup.sh" "${SCRIPT_DIR}/verify.sh"
  note "Kurulum tamamlandi."
}

main "$@"
