#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_VERSION="1.5"

GLOBAL_LOG_FILE="${SCRIPT_DIR}/log.txt"
LOG_FILE="$GLOBAL_LOG_FILE"
STATE_ROOT="/tmp/codex-manager"
CURRENT_PROJECT_FILE="${STATE_ROOT}/current_project.txt"
BASE_DIR_CANDIDATES=(
  "/opt/web"
  "/opt/web-projects"
)

DEFAULT_PROMPT="todo.md dosyasini oku ve kaldigin yerden devam et. todo.md icindeki aktif maddelere ve kullanici notlarina odaklan. Sadece gerekli dosyalari incele. Gerekli degisiklikleri uygula. Is bitince kisa bir ozet yaz, yaptigin kod degisikliklerini maddeler halinde kisa ozetle ve todo.md ile CHANGELOG.md dosyalarini gerekiyorsa guncelle."
REVIEW_PROMPT="Kod tabanini incele. Onceligi bug, regresyon, test eksigi ve risklere ver. Gerekirse duzeltmeleri uygula. Sonunda sadece kisa bir teknik ozet ver."
TEST_PROMPT="Projede test ve lint komutlarini bul. En mantikli dogrulama adimlarini calistir. Sorun varsa duzelt. Sonunda sadece sonuc, hata ve degisiklikleri kisa ozetle."

BASE_DIR=""
PROJECT_NAME=""
PROJECT_DIR=""
SESSION=""
STATE_DIR=""
LAST_PROMPT_FILE=""
DRAFT_PROMPT_FILE=""
AUTO_PID_FILE=""
AUTO_LOG_FILE=""
PROJECTS=()

COLOR=1
if [ ! -t 1 ] || [ "${NO_COLOR:-}" = "1" ]; then
  COLOR=0
fi

mkdir -p "$STATE_ROOT"
touch "$GLOBAL_LOG_FILE"

timestamp() {
  date '+%F %T'
}

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(timestamp)" "$level" "$*" >> "$LOG_FILE"
}

paint() {
  local code="$1"
  shift
  if [ "$COLOR" -eq 1 ]; then
    printf '\033[%sm%s\033[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

bold() { paint '1' "$*"; }
muted() { paint '2' "$*"; }
accent() { paint '36' "$*"; }
ok() { paint '32' "$*"; }
warn_color() { paint '33' "$*"; }
err_color() { paint '31' "$*"; }

info() {
  printf '%s\n' "$*"
  log INFO "$*"
}

warn() {
  printf '%s %s\n' "$(warn_color 'UYARI:')" "$*"
  log WARN "$*"
}

error() {
  printf '%s %s\n' "$(err_color 'HATA:')" "$*" >&2
  log ERROR "$*"
}

die() {
  error "$*"
  exit 1
}

on_error() {
  local exit_code="$1"
  local line_no="$2"
  local command="$3"
  error "Script hatasi. satir=${line_no} komut=${command} cikis=${exit_code}"
}

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

terminal_width() {
  local cols
  cols="$(tput cols 2>/dev/null || echo 80)"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  [ "$cols" -ge 60 ] || cols=60
  printf '%s' "$cols"
}

separator() {
  local width="${1:-$(terminal_width)}"
  printf '%*s' "$width" '' | tr ' ' '-'
}

strip_ansi() {
  printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

section_title() {
  printf '%s\n' "$(bold "$1")"
}

status_badge() {
  local state="$1"
  local label="$2"
  case "$state" in
    ok) printf '%s' "$(ok "[$label]")" ;;
    warn) printf '%s' "$(warn_color "[$label]")" ;;
    err) printf '%s' "$(err_color "[$label]")" ;;
    *) printf '%s' "$(muted "[$label]")" ;;
  esac
}

menu_item() {
  local key="$1"
  local title="$2"
  local desc="${3:-}"
  printf '  %s %s' "$(accent "[$key]")" "$title"
  if [ -n "$desc" ]; then
    printf '  %s' "$(muted "$desc")"
  fi
  printf '\n'
}

shorten() {
  local text="$1"
  local width="$2"
  local len="${#text}"
  if [ "$len" -le "$width" ]; then
    printf '%s' "$text"
  elif [ "$width" -le 3 ]; then
    printf '%.*s' "$width" "$text"
  else
    printf '%s...' "${text:0:$((width - 3))}"
  fi
}

pause_screen() {
  echo
  read -r -p "Devam icin Enter..." _
}

run_menu_action() {
  local status
  if "$@"; then
    status=0
  else
    status="$?"
  fi
  if [ "$status" -ne 0 ]; then
    log WARN "MENU_ACTION_FAILED action=$1 exit=$status"
  fi
  return 0
}

prompt_input() {
  local label="$1"
  local default_value="${2:-}"
  local answer
  if [ -n "$default_value" ]; then
    read -r -p "$label [$default_value]: " answer
    printf '%s' "${answer:-$default_value}"
  else
    read -r -p "$label: " answer
    printf '%s' "$answer"
  fi
}

sanitize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g'
}

check_tmux() {
  command -v tmux >/dev/null 2>&1 || die "tmux bulunamadi"
}

check_codex() {
  command -v codex >/dev/null 2>&1 || die "codex bulunamadi"
}

resolve_base_dir() {
  local candidate
  for candidate in "${BASE_DIR_CANDIDATES[@]}"; do
    if [ -d "$candidate" ]; then
      BASE_DIR="$candidate"
      return 0
    fi
  done
  die "Proje klasoru bulunamadi. Beklenen dizinlerden biri yok: ${BASE_DIR_CANDIDATES[*]}"
}

set_project_context() {
  local name="$1"
  PROJECT_NAME="$name"
  PROJECT_DIR="${BASE_DIR}/${PROJECT_NAME}"
  LOG_FILE="${PROJECT_DIR}/log.txt"
  SESSION="$(sanitize_name "$PROJECT_NAME")-codex"
  STATE_DIR="${STATE_ROOT}/$(sanitize_name "$PROJECT_NAME")"
  LAST_PROMPT_FILE="${STATE_DIR}/last_prompt.txt"
  DRAFT_PROMPT_FILE="${STATE_DIR}/draft_prompt.txt"
  AUTO_PID_FILE="${STATE_DIR}/auto_sender.pid"
  AUTO_LOG_FILE="${STATE_DIR}/auto_sender.log"
  mkdir -p "$STATE_DIR"
  touch "$LOG_FILE"
  log INFO "Proje baglami guncellendi: name=$PROJECT_NAME dir=$PROJECT_DIR session=$SESSION"
}

save_current_project() {
  [ -n "${PROJECT_NAME:-}" ] || return 0
  printf '%s' "$PROJECT_NAME" > "$CURRENT_PROJECT_FILE"
}

load_current_project() {
  [ -f "$CURRENT_PROJECT_FILE" ] || return 1
  local saved
  saved="$(cat "$CURRENT_PROJECT_FILE" 2>/dev/null || true)"
  [ -n "${saved:-}" ] || return 1
  [ -d "${BASE_DIR}/${saved}" ] || return 1
  set_project_context "$saved"
}

ensure_project_selected() {
  [ -n "${PROJECT_NAME:-}" ] || { warn "Once proje sec"; return 1; }
  [ -d "${PROJECT_DIR:-}" ] || { warn "Proje klasoru yok: ${PROJECT_DIR:-bos}"; return 1; }
}

session_exists() {
  ensure_project_selected >/dev/null 2>&1 || return 1
  tmux has-session -t "$SESSION" 2>/dev/null
}

ensure_session() {
  check_tmux
  ensure_project_selected || return 1
  session_exists || { warn "Oturum bulunamadi: $SESSION"; return 1; }
}

save_last_prompt() {
  printf '%s' "$1" > "$LAST_PROMPT_FILE"
}

save_prompt_draft() {
  ensure_project_selected || return 1
  printf '%s' "$1" > "$DRAFT_PROMPT_FILE"
  log INFO "Prompt taslagi kaydedildi. uzunluk=${#1}"
  info "Prompt taslagi kaydedildi"
}

load_last_prompt() {
  [ -f "$LAST_PROMPT_FILE" ] || return 1
  cat "$LAST_PROMPT_FILE"
}

load_prompt_draft() {
  [ -f "$DRAFT_PROMPT_FILE" ] || return 1
  cat "$DRAFT_PROMPT_FILE"
}

clear_prompt_draft() {
  ensure_project_selected || return 1
  [ -f "$DRAFT_PROMPT_FILE" ] || { warn "Temizlenecek taslak yok"; return 1; }
  rm -f "$DRAFT_PROMPT_FILE"
  info "Prompt taslagi temizlendi"
}

list_projects_array() {
  resolve_base_dir
  mapfile -t PROJECTS < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
}

render_project_list() {
  local i=1
  local project
  for project in "${PROJECTS[@]}"; do
    if [ "$project" = "${PROJECT_NAME:-}" ]; then
      printf '  %2d) %s %s\n' "$i" "$project" "$(ok '[aktif]')"
    else
      printf '  %2d) %s\n' "$i" "$project"
    fi
    i=$((i + 1))
  done
}

choose_project_interactive() {
  list_projects_array
  [ "${#PROJECTS[@]}" -gt 0 ] || { warn "Hic proje klasoru bulunamadi"; return 1; }

  while true; do
    render_dashboard
    echo
    printf '%s\n' "$(bold 'Proje Listesi')"
    render_project_list
    echo
    echo "Numara veya proje adinin bir parcasini gir."

    local answer normalized project
    read -r -p "Secim: " answer

    if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#PROJECTS[@]}" ]; then
      set_project_context "${PROJECTS[$((answer - 1))]}"
      save_current_project
      info "Aktif proje secildi: $PROJECT_NAME"
      return 0
    fi

    normalized="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    for project in "${PROJECTS[@]}"; do
      if printf '%s' "$project" | tr '[:upper:]' '[:lower:]' | grep -Fq "$normalized"; then
        set_project_context "$project"
        save_current_project
        info "Aktif proje secildi: $PROJECT_NAME"
        return 0
      fi
    done

    warn "Gecersiz secim: ${answer:-bos}"
    pause_screen
  done
}

project_file_status() {
  local file_name="$1"
  if [ -f "$PROJECT_DIR/$file_name" ]; then
    printf '%s' "$(ok 'var')"
  else
    printf '%s' "$(muted 'yok')"
  fi
}

auto_sender_running() {
  [ -n "${AUTO_PID_FILE:-}" ] || return 1
  [ -f "$AUTO_PID_FILE" ] || return 1
  local pid
  pid="$(cat "$AUTO_PID_FILE" 2>/dev/null || true)"
  [ -n "${pid:-}" ] || return 1
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  rm -f "$AUTO_PID_FILE"
  return 1
}

status_line() {
  local label="$1"
  local value="$2"
  local width value_width
  width="$(terminal_width)"
  value_width=$((width - 18))
  [ "$value_width" -ge 12 ] || value_width=12
  printf '%-14s %s\n' "$label" "$(shorten "$value" "$value_width")"
}

render_dashboard() {
  clear
  local session_text auto_text draft_text project_text

  if [ -n "${PROJECT_NAME:-}" ]; then
    project_text="$PROJECT_NAME"
  else
    project_text="secilmedi"
  fi

  if [ -n "${PROJECT_NAME:-}" ] && session_exists; then
    session_text="$(status_badge ok 'aktif')"
  else
    session_text="$(status_badge muted 'kapali')"
  fi

  if [ -n "${PROJECT_NAME:-}" ] && auto_sender_running; then
    auto_text="$(status_badge ok "aktif pid $(cat "$AUTO_PID_FILE")")"
  else
    auto_text="$(status_badge muted 'kapali')"
  fi

  if [ -n "${PROJECT_NAME:-}" ] && [ -f "${DRAFT_PROMPT_FILE:-/dev/null}" ]; then
    draft_text="$(status_badge ok 'kayitli')"
  else
    draft_text="$(status_badge muted 'yok')"
  fi

  printf '%s\n' "$(separator)"
  printf '%s\n' "$(bold "CODEXIFY ${APP_VERSION}")"
  printf '%s\n' "$(muted 'Tmux + Codex oturum yonetimi')"
  printf '%s\n' "$(separator)"
  section_title "Genel Durum"
  status_line "Proje" "$(strip_ansi "$project_text")"
  status_line "Klasor" "${PROJECT_DIR:-yok}"
  status_line "Session" "$(strip_ansi "${SESSION:-yok}") / $(strip_ansi "$session_text")"
  status_line "Taslak" "$(strip_ansi "$draft_text")"
  status_line "Auto" "$(strip_ansi "$auto_text")"
  if [ -n "${PROJECT_NAME:-}" ]; then
    status_line "todo/changelog" "todo=$(strip_ansi "$(project_file_status todo.md)") changelog=$(strip_ansi "$(project_file_status CHANGELOG.md)")"
  fi
  printf '%s\n' "$(separator)"
  section_title "Kisa Bilgi"
  printf '  Detach: tmux icindeyken %s\n' "$(bold 'Ctrl+b sonra d')"
  printf '  Auto gonderim artik promptu ekrana dustugunu kontrol ederek Enter basar\n'
  printf '%s\n' "$(separator)"
  if [ -n "${PROJECT_NAME:-}" ]; then
    section_title "Aktif Proje Ozet"
    printf '  %s %s\n' "$(status_badge ok 'todo')" "$(project_file_status todo.md)"
    printf '  %s %s\n' "$(status_badge ok 'CHANGELOG')" "$(project_file_status CHANGELOG.md)"
    printf '%s\n' "$(separator)"
  fi
}

show_main_menu() {
  render_dashboard
  echo
  section_title "Ana Menu"
  menu_item "1" "Proje ve Oturum" "Proje secimi, tmux oturumu, attach ve izinler"
  menu_item "2" "Prompt ve Otomasyon" "Promptlar, loglar, snapshot ve auto sender"
  menu_item "S" "Durum" "Anlik durum ozetini goster"
  menu_item "Q" "Cikis" "Scripti kapat"
  echo
}

read_multiline_prompt() {
  local line prompt=""
  echo "Promptu yaz. Bitirmek icin bos satir birak."
  echo
  while IFS= read -r line; do
    [ -z "$line" ] && break
    [ -z "$prompt" ] || prompt+=$'\n'
    prompt+="$line"
  done
  printf '%s' "$prompt"
}

pane_snapshot() {
  tmux capture-pane -t "$SESSION" -pS -220 2>/dev/null || true
}

clean_pane_output() {
  sed 's/\r//g; s/\x1b\[[0-9;]*[[:alpha:]]//g'
}

pane_ready_for_input() {
  ensure_session >/dev/null 2>&1 || return 1
  local recent
  recent="$(pane_snapshot | clean_pane_output | tail -n 40)"
  printf '%s\n' "$recent" | grep -Eq '^[[:space:]]*[›>❯»] ' && return 0
  printf '%s\n' "$recent" | grep -Eq '(^|[[:space:]])(/status|Permissions|Approve|Continue)([[:space:]]|$)' && return 0
  return 1
}

wait_for_session_ready() {
  local timeout="${1:-900}"
  local waited=0
  while [ "$waited" -lt "$timeout" ]; do
    ensure_session >/dev/null 2>&1 || return 1
    if pane_ready_for_input; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

extract_codex_summary() {
  ensure_session >/dev/null 2>&1 || return 1
  pane_snapshot | clean_pane_output | awk '
    {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "") next
      if (line ~ /^› /) next
      if (line ~ /^• Explored$/) next
      if (line ~ /^─+$/) next
      if (line ~ /^> /) next
      if (line ~ /^[[:alnum:]_.-]+@[[:alnum:]_.-]+:[^$#]*[$#]$/) next
      if (line ~ /^gpt-[0-9.]+/) next
      lines[++count]=line
    }
    END {
      start=(count > 4 ? count - 3 : 1)
      out=""
      for (i=start; i<=count; i++) {
        if (lines[i] == "") continue
        if (out != "") out=out " | "
        out=out lines[i]
      }
      print out
    }
  ' | sed 's/[[:space:]]\+/ /g' | cut -c1-320
}

log_codex_summary() {
  local source="$1"
  local summary
  summary="$(extract_codex_summary || true)"
  [ -n "${summary:-}" ] || return 0
  log INFO "CODEX_SUMMARY[$source] $summary"
}

log_git_summary() {
  ensure_project_selected >/dev/null 2>&1 || return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local files shortstat normalized
  files="$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  shortstat="$(git -C "$PROJECT_DIR" diff --shortstat 2>/dev/null || true)"
  normalized="$(printf '%s' "$shortstat" | sed 's/^[[:space:]]*//; s/[[:space:]]\+/ /g')"

  if [ -n "$normalized" ]; then
    log INFO "GIT_SUMMARY files=$files $normalized"
  else
    log INFO "GIT_SUMMARY files=$files changes=clean-or-untracked-only"
  fi
}

send_enter() {
  tmux send-keys -t "$SESSION" Enter
}

prompt_signature() {
  local prompt="$1"
  printf '%s\n' "$prompt" | awk 'NF { print; exit }' | cut -c1-80
}

prompt_visible_in_pane() {
  local signature="$1"
  [ -n "${signature:-}" ] || return 0
  pane_snapshot | clean_pane_output | tail -n 50 | grep -Fq "$signature"
}

paste_prompt_buffer() {
  local prompt="$1"
  tmux set-buffer -- "$prompt"
  if tmux paste-buffer -p -t "$SESSION" 2>/dev/null; then
    return 0
  fi
  tmux paste-buffer -t "$SESSION"
}

send_prompt_to_session() {
  local prompt="$1"
  local signature tries=0
  ensure_session || return 1
  [ -n "${prompt:-}" ] || { warn "Prompt bos olamaz"; return 1; }

  signature="$(prompt_signature "$prompt")"

  tmux send-keys -t "$SESSION" Escape
  sleep 0.20

  while [ "$tries" -lt 3 ]; do
    tries=$((tries + 1))
    paste_prompt_buffer "$prompt" || true
    sleep 0.35
    if prompt_visible_in_pane "$signature"; then
      log INFO "PROMPT_BUFFER_OK attempt=$tries signature=$(printf '%s' "$signature" | tr ' ' '_')"
      send_enter
      return 0
    fi
    log WARN "PROMPT_BUFFER_RETRY attempt=$tries signature=$(printf '%s' "$signature" | tr ' ' '_')"
    tmux send-keys -t "$SESSION" Escape
    sleep 0.25
  done

  warn "Prompt ekranda dogrulanamadi, son deneme ile Enter gonderiliyor"
  send_enter
}

enable_full_permissions() {
  ensure_session || return
  if ! wait_for_session_ready 900; then
    warn "Codex girdi icin hazir degil"
    return 1
  fi

  log INFO "Full access secimi gonderiliyor"
  tmux send-keys -t "$SESSION" Escape
  sleep 0.15
  tmux send-keys -t "$SESSION" "/permissions"
  sleep 0.15
  send_enter
  sleep 0.50
  tmux send-keys -t "$SESSION" "2"
  sleep 0.20
  send_enter
  sleep 0.50
  tmux send-keys -t "$SESSION" Escape
  info "Full access secimi gonderildi"
}

send_prompt_core() {
  local prompt="$1"
  local source="${2:-manual}"
  ensure_session || return 1
  [ -n "${prompt:-}" ] || { warn "Prompt bos olamaz"; return 1; }

  if ! wait_for_session_ready 120; then
    warn "Hazir ekran algilanamadi, prompt yine de gonderiliyor"
    log WARN "PROMPT_READY_TIMEOUT[$source] forced_send=1"
  fi

  save_last_prompt "$prompt"
  log INFO "PROMPT_SEND[$source] uzunluk=${#prompt}"
  send_prompt_to_session "$prompt" || return 1
  sleep 0.30
  info "Prompt gonderildi"
}

start_session() {
  check_tmux
  check_codex
  ensure_project_selected || return

  if session_exists; then
    info "Oturum zaten var: $SESSION"
    return 0
  fi

  tmux new-session -d -s "$SESSION" "cd \"$PROJECT_DIR\" && codex"
  log INFO "Yeni tmux oturumu baslatildi: $SESSION"
  sleep 1
  info "Oturum baslatildi: $SESSION"
}

show_attach_help() {
  printf '%s\n' "$(separator)"
  section_title "Attach Bilgisi"
  printf '  Tmux ekranindan cikmak icin %s kullan.\n' "$(bold 'Ctrl+b sonra d')"
  printf '  Bu sadece detach yapar, codex oturumu arka planda calismaya devam eder.\n'
  printf '  Oturumu tamamen kapatmak istersen menuden "Oturumu kapat" sec.\n'
  printf '%s\n' "$(separator)"
}

attach_session() {
  ensure_session || return
  show_attach_help
  read -r -p "Baglanmak icin Enter..." _
  log INFO "Tmux oturumuna baglaniliyor: $SESSION"
  tmux attach -t "$SESSION"
}

list_sessions() {
  check_tmux
  local output
  output="$(tmux ls 2>&1 || true)"
  if [ -n "${output:-}" ]; then
    printf '%s\n' "$output"
  else
    warn "Acik tmux oturumu yok"
  fi
}

stop_session() {
  check_tmux
  ensure_project_selected || return
  stop_auto_sender >/dev/null 2>&1 || true
  if ! session_exists; then
    warn "Oturum zaten yok: $SESSION"
    return 0
  fi
  tmux kill-session -t "$SESSION"
  log INFO "Tmux oturumu kapatildi: $SESSION"
  info "Oturum kapatildi: $SESSION"
}

save_default_prompt_draft() {
  save_prompt_draft "$DEFAULT_PROMPT"
}

save_review_prompt_draft() {
  save_prompt_draft "$REVIEW_PROMPT"
}

save_test_prompt_draft() {
  save_prompt_draft "$TEST_PROMPT"
}

save_custom_prompt_draft() {
  ensure_project_selected || return
  local prompt
  prompt="$(read_multiline_prompt)"
  [ -n "${prompt:-}" ] || { warn "Prompt girilmedi"; return 1; }
  save_prompt_draft "$prompt"
}

send_draft_prompt() {
  ensure_session || return
  local prompt
  prompt="$(load_prompt_draft)" || { warn "Kayitli taslak prompt yok"; return 1; }
  [ -n "${prompt:-}" ] || { warn "Kayitli taslak bos"; return 1; }
  send_prompt_core "$prompt" "draft"
}

send_last_prompt() {
  ensure_session || return
  local prompt
  prompt="$(load_last_prompt)" || { warn "Kayitli son prompt yok"; return 1; }
  [ -n "${prompt:-}" ] || { warn "Kayitli prompt bos"; return 1; }
  send_prompt_core "$prompt" "repeat"
}

show_last_prompt() {
  ensure_project_selected || return
  [ -f "$LAST_PROMPT_FILE" ] || { warn "Kayitli son prompt yok"; return 1; }
  printf '%s\n' "$(separator)"
  cat "$LAST_PROMPT_FILE"
  printf '%s\n' "$(separator)"
}

show_prompt_draft() {
  ensure_project_selected || return
  [ -f "$DRAFT_PROMPT_FILE" ] || { warn "Kayitli taslak prompt yok"; return 1; }
  printf '%s\n' "$(separator)"
  cat "$DRAFT_PROMPT_FILE"
  printf '%s\n' "$(separator)"
}

send_status_command() {
  ensure_session || return
  if ! wait_for_session_ready 900; then
    warn "Codex girdi icin hazir degil"
    return 1
  fi
  tmux send-keys -t "$SESSION" Escape
  sleep 0.15
  tmux send-keys -t "$SESSION" "/status"
  sleep 0.15
  send_enter
  log INFO "STATUS_COMMAND sent"
  info "/status gonderildi"
}

tail_output() {
  ensure_session || return
  local lines="${1:-40}"
  local start="${2:--160}"
  [[ "$lines" =~ ^[0-9]+$ ]] || { warn "Gecersiz satir sayisi"; return 1; }
  [[ "$start" =~ ^-?[0-9]+$ ]] || { warn "Gecersiz baslangic"; return 1; }
  tmux capture-pane -t "$SESSION" -pS "$start" | tail -n "$lines"
}

show_debug_snapshot() {
  ensure_session || return
  printf '%s\n' "$(separator)"
  pane_snapshot | tail -n 40
  printf '%s\n' "$(separator)"
  log_codex_summary "snapshot"
}

show_script_log() {
  local lines="${1:-60}"
  [[ "$lines" =~ ^[0-9]+$ ]] || { warn "Gecersiz satir sayisi"; return 1; }
  [ -f "$LOG_FILE" ] || { warn "Log dosyasi yok: $LOG_FILE"; return 1; }
  printf '%s\n' "$(separator)"
  tail -n "$lines" "$LOG_FILE"
  printf '%s\n' "$(separator)"
}

show_auto_sender_log() {
  ensure_project_selected || return
  local lines="${1:-60}"
  [[ "$lines" =~ ^[0-9]+$ ]] || { warn "Gecersiz satir sayisi"; return 1; }
  [ -f "$AUTO_LOG_FILE" ] || { warn "Auto sender logu yok"; return 1; }
  printf '%s\n' "$(separator)"
  tail -n "$lines" "$AUTO_LOG_FILE"
  printf '%s\n' "$(separator)"
}

start_auto_sender() {
  ensure_session || return
  [ -f "$DRAFT_PROMPT_FILE" ] || { warn "Once taslak prompt kaydet"; return 1; }
  if auto_sender_running; then
    warn "Otomatik gonderici zaten calisiyor"
    return 1
  fi

  local count="$1"
  local minutes="$2"
  local start_mode="${3:-now}"
  local interval prompt

  [[ "$count" =~ ^[0-9]+$ ]] || { warn "Gecersiz adet"; return 1; }
  [ "$count" -gt 0 ] || { warn "Adet 0'dan buyuk olmali"; return 1; }
  [[ "$minutes" =~ ^[0-9]+([.][0-9]+)?$ ]] || { warn "Gecersiz dakika"; return 1; }

  interval="$(awk "BEGIN { printf \"%d\", ($minutes * 60) }")"
  [ "$interval" -gt 0 ] || { warn "Sure 0'dan buyuk olmali"; return 1; }
  prompt="$(load_prompt_draft)"

  log INFO "AUTO_START count=$count minutes=$minutes mode=$start_mode"

  (
    cleanup_auto_sender() {
      rm -f "$AUTO_PID_FILE"
    }
    trap cleanup_auto_sender EXIT

    local i=1
    local cycle_waited

    if [ "$start_mode" = "wait" ]; then
      sleep "$interval"
    fi

    while [ "$i" -le "$count" ]; do
      if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        printf '[%s] [%s] session bulunamadi, auto sender durdu\n' "$(timestamp)" "$PROJECT_NAME" >> "$AUTO_LOG_FILE"
        log WARN "AUTO_STOP session_missing"
        break
      fi

      cycle_waited=0
      if ! wait_for_session_ready 120; then
        cycle_waited=120
        printf '[%s] [%s] tur %s icin hazir ekran algilanamadi, dogrulamali gonderim deneniyor\n' "$(timestamp)" "$PROJECT_NAME" "$i" >> "$AUTO_LOG_FILE"
        log WARN "AUTO_READY_TIMEOUT index=$i forced_send=1"
      fi

      if ! send_prompt_to_session "$prompt"; then
        printf '[%s] [%s] tur %s gonderilemedi, auto sender durdu\n' "$(timestamp)" "$PROJECT_NAME" "$i" >> "$AUTO_LOG_FILE"
        log WARN "AUTO_STOP send_failed index=$i"
        break
      fi
      save_last_prompt "$prompt"

      printf '[%s] [%s] gonderim %s/%s tamamlandi\n' "$(timestamp)" "$PROJECT_NAME" "$i" "$count" >> "$AUTO_LOG_FILE"
      log INFO "AUTO_SEND $i/$count waited=${cycle_waited}s"

      if wait_for_session_ready 900; then
        log_codex_summary "auto-$i"
        log_git_summary
      else
        log WARN "AUTO_WAIT_TIMEOUT after_send index=$i"
      fi

      if [ "$i" -lt "$count" ]; then
        sleep "$interval"
      fi
      i=$((i + 1))
    done

    log INFO "AUTO_DONE count=$count"
  ) >/dev/null 2>&1 &

  echo $! > "$AUTO_PID_FILE"
  info "Otomatik gonderici baslatildi"
}

start_auto_sender_interactive() {
  local count minutes mode answer
  read -r -p "Kac kere gondersin: " count
  read -r -p "Kac dakikada bir gondersin: " minutes
  echo "Ilk gonderim: 1) hemen  2) bekle"
  read -r -p "Secim [1]: " answer
  mode="now"
  if [ "${answer:-1}" = "2" ]; then
    mode="wait"
  fi
  start_auto_sender "$count" "$minutes" "$mode"
}

stop_auto_sender() {
  if auto_sender_running; then
    local pid
    pid="$(cat "$AUTO_PID_FILE")"
    kill "$pid" 2>/dev/null || true
    rm -f "$AUTO_PID_FILE"
    log INFO "AUTO_STOP pid=$pid"
    info "Otomatik gonderici durduruldu"
  else
    warn "Otomatik gonderici calismiyor"
  fi
}

show_status() {
  render_dashboard
  if session_exists; then
    echo
    printf '%s\n' "$(bold 'Son Cikti')"
    printf '%s\n' "$(separator)"
    tail_output 16 -120 || true
    printf '%s\n' "$(separator)"
    log_codex_summary "status"
  fi
}

show_workspace_menu() {
  while true; do
    render_dashboard
    echo
    section_title "Proje ve Oturum"
    printf '%s\n' "$(separator)"
    echo "  1) Proje sec"
    echo "  2) Durumu yenile"
    echo "  3) Oturumu baslat"
    echo "  4) Oturuma baglan"
    echo "  5) Oturumlari listele"
    echo "  6) Oturumu kapat"
    echo "  7) Full access sec"
    echo "  8) Geri don"
    echo
    case "$(prompt_input "Secim")" in
      1) run_menu_action choose_project_interactive ;;
      2) run_menu_action show_status ;;
      3) run_menu_action start_session ;;
      4) run_menu_action attach_session ;;
      5) run_menu_action list_sessions ;;
      6) run_menu_action stop_session ;;
      7) run_menu_action enable_full_permissions ;;
      8) return 0 ;;
      *) warn "Gecersiz secim" ;;
    esac
    pause_screen
  done
}

show_operations_menu() {
  while true; do
    render_dashboard
    echo
    section_title "Prompt ve Otomasyon"
    printf '%s\n' "$(separator)"
    echo "  Prompt"
    echo "    1) Varsayilan taslagi kaydet"
    echo "    2) Inceleme taslagi kaydet"
    echo "    3) Test taslagi kaydet"
    echo "    4) Ozel prompt yaz ve taslaga kaydet"
    echo "    5) Taslagi gonder"
    echo "    6) Son promptu tekrar gonder"
    echo "    7) Taslagi goster"
    echo "    8) Son promptu goster"
    echo "    9) Taslagi temizle"
    echo "   10) /status gonder"
    echo
    echo "  Izleme"
    echo "   11) Son ciktiyi goster"
    echo "   12) Snapshot goster"
    echo "   13) Script logunu goster"
    echo "   14) Auto sender logunu goster"
    echo "   15) Durum ekrani"
    echo
    echo "  Otomasyon"
    echo "   16) Otomatik gondericiyi baslat"
    echo "   17) Otomatik gondericiyi durdur"
    echo "   18) Geri don"
    echo
    case "$(prompt_input "Secim")" in
      1) run_menu_action save_default_prompt_draft ;;
      2) run_menu_action save_review_prompt_draft ;;
      3) run_menu_action save_test_prompt_draft ;;
      4) run_menu_action save_custom_prompt_draft ;;
      5) run_menu_action send_draft_prompt ;;
      6) run_menu_action send_last_prompt ;;
      7) run_menu_action show_prompt_draft ;;
      8) run_menu_action show_last_prompt ;;
      9) run_menu_action clear_prompt_draft ;;
      10) run_menu_action send_status_command ;;
      11) run_menu_action tail_output ;;
      12) run_menu_action show_debug_snapshot ;;
      13) run_menu_action show_script_log ;;
      14) run_menu_action show_auto_sender_log ;;
      15) run_menu_action show_status ;;
      16) run_menu_action start_auto_sender_interactive ;;
      17) run_menu_action stop_auto_sender ;;
      18) return 0 ;;
      *) warn "Gecersiz secim" ;;
    esac
    pause_screen
  done
}

bootstrap_project() {
  resolve_base_dir
  load_current_project || true
}

interactive_loop() {
  local choice
  while true; do
    show_main_menu
    choice="$(prompt_input "Secim")"
    log INFO "MAIN_MENU choice=${choice:-bos}"
    case "$choice" in
      1|p|P|o|O) run_menu_action show_workspace_menu ;;
      2|r|R|i|I|a|A) run_menu_action show_operations_menu ;;
      s|S) run_menu_action show_status; pause_screen ;;
      q|Q)
        info "Script kapatiliyor"
        exit 0
        ;;
      *)
        warn "Gecersiz secim"
        pause_screen
        ;;
    esac
  done
}

bootstrap_project
log INFO "Script basladi: $SCRIPT_NAME"
interactive_loop
