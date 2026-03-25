#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

source "${ROOT_DIR}/codexify.sh"

TEST_TMP_DIR="$(mktemp -d)"
LOG_FILE="${TEST_TMP_DIR}/test.log"
SESSION="test-session"
SNAPSHOT_COUNTER_FILE="${TEST_TMP_DIR}/snapshot_counter"
STATE_ROOT="${TEST_TMP_DIR}/state"
CURRENT_PROJECT_FILE="${STATE_ROOT}/current_project.txt"
BASE_DIR_FILE="${STATE_ROOT}/base_dir.txt"
mkdir -p "$STATE_ROOT"

assert_ok() {
  local name="$1"
  shift
  if "$@"; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s\n' "$name" >&2
    exit 1
  fi
}

assert_fail() {
  local name="$1"
  shift
  if "$@"; then
    printf 'not ok - %s\n' "$name" >&2
    exit 1
  else
    printf 'ok - %s\n' "$name"
  fi
}

SNAPSHOT_BEFORE=$'onceki cikti\n› PLAN.md dosyasini oku ve kaldigin yerden devam et.'
SNAPSHOT_AFTER_SAME_HISTORY=$'onceki cikti\n› PLAN.md dosyasini oku ve kaldigin yerden devam et.\n/transcripts'
SNAPSHOT_AFTER_WITH_NEW_PROMPT=$'onceki cikti\n› PLAN.md dosyasini oku ve kaldigin yerden devam et.\n› PLAN.md dosyasini oku ve kaldigin yerden devam et.'
SNAPSHOT_BEFORE_WRAPPED=$'onceki cikti\n› PLAN.md dosyasini oku ve\n  kaldigin yerden devam et.'
SNAPSHOT_AFTER_SAME_WRAPPED_HISTORY=$'onceki cikti\n› PLAN.md dosyasini oku ve\n  kaldigin yerden devam et.\n/transcripts'
SNAPSHOT_AFTER_WITH_NEW_WRAPPED_PROMPT=$'onceki cikti\n› PLAN.md dosyasini oku ve\n  kaldigin yerden devam et.\n› PLAN.md dosyasini oku ve\n  kaldigin yerden devam et.'
signature='PLAN.md dosyasini oku ve kaldigin yerden devam et.'

assert_fail \
  "prompt_paste_verified eski eslesmeyi yeni yapistirma sanmaz" \
  prompt_paste_verified "$signature" "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER_SAME_HISTORY"

assert_ok \
  "prompt_paste_verified yeni prompt gorunur oldugunda gecer" \
  prompt_paste_verified "$signature" "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER_WITH_NEW_PROMPT"

assert_fail \
  "prompt_paste_verified satira kirilmis eski eslesmeyi yeni yapistirma sanmaz" \
  prompt_paste_verified "$signature" "$SNAPSHOT_BEFORE_WRAPPED" "$SNAPSHOT_AFTER_SAME_WRAPPED_HISTORY"

assert_ok \
  "prompt_paste_verified satira kirilan yeni promptu algilar" \
  prompt_paste_verified "$signature" "$SNAPSHOT_BEFORE_WRAPPED" "$SNAPSHOT_AFTER_WITH_NEW_WRAPPED_PROMPT"

multiline_prompt_result="$(
  read_multiline_prompt 2>/dev/null <<'EOF'
ilk satir
ikinci satir

EOF
)"

[ "$multiline_prompt_result" = $'ilk satir\nikinci satir' ] || {
  printf 'not ok - read_multiline_prompt sadece girilen metni donmeli\n' >&2
  exit 1
}
printf 'ok - read_multiline_prompt sadece girilen metni doner\n'

case "$multiline_prompt_result" in
  *"Promptu yaz. Bitirmek icin bos satir birak."*|*"-----"*)
    printf 'not ok - read_multiline_prompt aciklama veya separator eklememeli\n' >&2
    exit 1
    ;;
esac
printf 'ok - read_multiline_prompt aciklama metnini dahil etmez\n'

sleep() { :; }
ensure_session() { return 0; }
reset_prompt_input_area() { :; }

pane_snapshot() {
  local calls=0
  if [ -f "$SNAPSHOT_COUNTER_FILE" ]; then
    calls="$(cat "$SNAPSHOT_COUNTER_FILE")"
  fi

  if [ "${SNAPSHOT_MODE:-}" = "success" ]; then
    if [ $((calls % 2)) -eq 0 ]; then
      printf '%s\n' "$SNAPSHOT_BEFORE"
    else
      printf '%s\n' "$SNAPSHOT_AFTER_WITH_NEW_PROMPT"
    fi
  else
    if [ $((calls % 2)) -eq 0 ]; then
      printf '%s\n' "$SNAPSHOT_BEFORE"
    else
      printf '%s\n' "$SNAPSHOT_AFTER_SAME_HISTORY"
    fi
  fi
  printf '%s' "$((calls + 1))" > "$SNAPSHOT_COUNTER_FILE"
}

PASTE_BUFFER_CALLS=0
SEND_KEYS_LOG=()
SEND_ENTER_CALLS=0

tmux() {
  if [ "${1:-}" = "send-keys" ]; then
    SEND_KEYS_LOG+=("$*")
    case " $* " in
      *" C-m "*) SEND_ENTER_CALLS=$((SEND_ENTER_CALLS + 1)) ;;
    esac
    return 0
  fi
  if [ "${1:-}" = "set-buffer" ]; then
    return 0
  fi
  if [ "${1:-}" = "paste-buffer" ]; then
    shift
    for arg in "$@"; do
      if [ "$arg" = "-p" ]; then
        printf 'not ok - tmux paste-buffer -p kullanilmamali\n' >&2
        exit 1
      fi
    done
    PASTE_BUFFER_CALLS=$((PASTE_BUFFER_CALLS + 1))
    return 0
  fi
  return 0
}

PASTE_BUFFER_CALLS=0
assert_ok \
  "paste_prompt_buffer tmux paste-buffer komutunu plain modda kullanir" \
  paste_prompt_buffer "deneme promptu"
[ "$PASTE_BUFFER_CALLS" -eq 1 ] || {
  printf 'not ok - paste-buffer bir kez cagrilmali\n' >&2
  exit 1
}
printf 'ok - paste-buffer plain modda cagrildi\n'

SNAPSHOT_MODE="failure"
printf '0' > "$SNAPSHOT_COUNTER_FILE"
SEND_ENTER_CALLS=0
assert_fail \
  "send_prompt_to_session eski pane gecmisine guvenip Enter gondermez" \
  send_prompt_to_session "PLAN.md dosyasini oku ve kaldigin yerden devam et."
[ "$SEND_ENTER_CALLS" -eq 0 ] || {
  printf 'not ok - failure durumunda Enter gonderilmemeli\n' >&2
  exit 1
}
printf 'ok - failure durumunda Enter gonderilmedi\n'

SNAPSHOT_MODE="success"
printf '0' > "$SNAPSHOT_COUNTER_FILE"
SEND_ENTER_CALLS=0
PASTE_BUFFER_CALLS=0
assert_ok \
  "send_prompt_to_session yeni prompt gorunurse Enter gonderir" \
  send_prompt_to_session "PLAN.md dosyasini oku ve kaldigin yerden devam et."
[ "$SEND_ENTER_CALLS" -eq 1 ] || {
  printf 'not ok - success durumunda tek Enter gonderilmeli\n' >&2
  exit 1
}
printf 'ok - success durumunda tek Enter gonderildi\n'
[ "$PASTE_BUFFER_CALLS" -eq 1 ] || {
  printf 'not ok - success durumunda paste-buffer bir kez cagrilmali\n' >&2
  exit 1
}
printf 'ok - success durumunda plain paste-buffer kullanildi\n'

SEND_KEYS_LOG=()
send_enter
[ "${#SEND_KEYS_LOG[@]}" -eq 1 ] || {
  printf 'not ok - send_enter tek komut gondermeli\n' >&2
  exit 1
}
[ "${SEND_KEYS_LOG[0]}" = "send-keys -t $SESSION C-m" ] || {
  printf 'not ok - send_enter C-m kullanmali\n' >&2
  exit 1
}
printf 'ok - send_enter C-m kullandi\n'

SESSION_EXISTS_CALLS=0
NEW_SENT=0
check_tmux() { :; }
check_codex() { :; }
ensure_project_selected() { return 0; }
wait_for_session_ready() { return 0; }
send_prompt_to_session() {
  if [ "${1:-}" = "$NEW_SESSION_COMMAND" ]; then
    NEW_SENT=$((NEW_SENT + 1))
  fi
  return 0
}
info() { :; }
log() { :; }
session_exists() {
  SESSION_EXISTS_CALLS=$((SESSION_EXISTS_CALLS + 1))
  if [ "$SESSION_EXISTS_CALLS" -eq 1 ]; then
    return 1
  fi
  return 0
}
SEND_KEYS_LOG=()
start_session
[ "$NEW_SENT" -eq 1 ] || {
  printf 'not ok - start_session /new gondermeli\n' >&2
  exit 1
}
printf 'ok - start_session /new gonderdi\n'

SESSION_EXISTS_CALLS=0
SESSION_COMMAND_SEQUENCE=("codex" "codex" "bash")
SESSION_COMMAND_INDEX=0
check_tmux() { :; }
ensure_project_selected() { return 0; }
stop_auto_sender() { return 0; }
session_exists() {
  SESSION_EXISTS_CALLS=$((SESSION_EXISTS_CALLS + 1))
  [ "$SESSION_EXISTS_CALLS" -le 4 ]
}
session_command_name() {
  local idx="$SESSION_COMMAND_INDEX"
  if [ "$idx" -ge "${#SESSION_COMMAND_SEQUENCE[@]}" ]; then
    idx=$((${#SESSION_COMMAND_SEQUENCE[@]} - 1))
  fi
  printf '%s\n' "${SESSION_COMMAND_SEQUENCE[$idx]}"
  SESSION_COMMAND_INDEX=$((SESSION_COMMAND_INDEX + 1))
}
SEND_KEYS_LOG=()
stop_session
printf '%s\n' "${SEND_KEYS_LOG[@]}" | grep -Fq "send-keys -t $SESSION C-c" || {
  printf 'not ok - stop_session once C-c gondermeli\n' >&2
  exit 1
}
printf '%s\n' "${SEND_KEYS_LOG[@]}" | grep -Fq "send-keys -t $SESSION C-d" || {
  printf 'not ok - stop_session gerekirse C-d gondermeli\n' >&2
  exit 1
}
printf 'ok - stop_session codexi nazikce kapatmayi denedi\n'

MENU_ACTIONS=()
run_menu_action() {
  MENU_ACTIONS+=("$1")
  return 0
}
pause_screen() { :; }
warn() { :; }

MENU_ACTIONS=()
assert_ok \
  "handle_workspace_menu_choice oturum kapatma secenegini dogru fonksiyona baglar" \
  handle_workspace_menu_choice 7
[ "${MENU_ACTIONS[0]}" = "stop_session" ] || {
  printf 'not ok - workspace menu 7 stop_session cagirmali\n' >&2
  exit 1
}
printf 'ok - workspace menu 7 stop_session cagirdi\n'

MENU_ACTIONS=()
assert_fail \
  "handle_workspace_menu_choice geri donuste donguden cikar" \
  handle_workspace_menu_choice 9

MENU_ACTIONS=()
assert_ok \
  "handle_workspace_menu_choice root klasoru secenegini dogru fonksiyona baglar" \
  handle_workspace_menu_choice 2
[ "${MENU_ACTIONS[0]}" = "set_base_dir_interactive" ] || {
  printf 'not ok - workspace menu 2 set_base_dir_interactive cagirmali\n' >&2
  exit 1
}
printf 'ok - workspace menu 2 set_base_dir_interactive cagirdi\n'

BASE_DIR=""
printf '%s' "$TEST_TMP_DIR" > "$BASE_DIR_FILE"
assert_ok \
  "resolve_base_dir kayitli root klasorunu yukler" \
  resolve_base_dir
[ "$BASE_DIR" = "$TEST_TMP_DIR" ] || {
  printf 'not ok - resolve_base_dir kayitli root klasorunu kullanmali\n' >&2
  exit 1
}
printf 'ok - resolve_base_dir kayitli root klasorunu kullandi\n'

MENU_ACTIONS=()
assert_ok \
  "handle_operations_menu_choice auto stop secenegini dogru fonksiyona baglar" \
  handle_operations_menu_choice 19
[ "${MENU_ACTIONS[0]}" = "stop_auto_sender" ] || {
  printf 'not ok - operations menu 19 stop_auto_sender cagirmali\n' >&2
  exit 1
}
printf 'ok - operations menu 19 stop_auto_sender cagirdi\n'

MENU_ACTIONS=()
assert_ok \
  "handle_github_menu_choice pull secenegini dogru fonksiyona baglar" \
  handle_github_menu_choice 2
[ "${MENU_ACTIONS[0]}" = "run_github_pull_only" ] || {
  printf 'not ok - github menu 2 run_github_pull_only cagirmali\n' >&2
  exit 1
}
printf 'ok - github menu 2 run_github_pull_only cagirdi\n'

SESSION_OPEN=1
PROJECT_NAME='demo'
PROJECT_DIR="$TEST_TMP_DIR/demo"
SESSION='demo-codex'
mkdir -p "$PROJECT_DIR"
session_exists() {
  [ "${SESSION_OPEN:-0}" -eq 1 ]
}
info() { :; }
warn() { :; }
assert_fail \
  "confirm_script_exit sadece scripti kapatir" \
  confirm_script_exit
[ "${SESSION_OPEN:-0}" -eq 1 ] || {
  printf 'not ok - confirm_script_exit oturumu kapatmamalı\n' >&2
  exit 1
}
printf 'ok - confirm_script_exit oturumu kapatmadi\n'

rm -f "$PROJECT_DIR/PLAN.md" "$PROJECT_DIR/CHANGELOG.md"
assert_ok \
  "missing_required_md_files dosyalar eksikken true doner" \
  missing_required_md_files
printf 'ok - missing_required_md_files eksik dosyalari algiladi\n'

printf '%s' 'tamam' > "$PROJECT_DIR/PLAN.md"
printf '%s' 'tamam' > "$PROJECT_DIR/CHANGELOG.md"
assert_fail \
  "missing_required_md_files dosyalar tamken false doner" \
  missing_required_md_files
printf 'ok - missing_required_md_files tam dosyalarda false dondu\n'

rm -rf "$TEST_TMP_DIR"
