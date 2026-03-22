#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_LOG_FILE="${SCRIPT_DIR}/log.txt"
LOG_FILE="$GLOBAL_LOG_FILE"
STATE_ROOT="/tmp/codex-manager"
CURRENT_PROJECT_FILE="${STATE_ROOT}/current_project.txt"
DEFAULT_PROMPT="todo.md dosyasini oku ve kaldigin yerden devam et. todo.md icindeki aktif maddeye odaklan. Sadece gerekli dosyalari incele. Gerekli degisiklikleri uygula. Is bitince kisa bir ozet yaz, yaptigin kod degisikliklerini maddeler halinde ozetle ve todo.md ile CHANGELOG.md dosyalarini gerekiyorsa guncelle."

BASE_DIR_CANDIDATES=(
  "/opt/web"
  "/opt/web-projects"
)

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

info() {
  echo "$*"
  log INFO "$*"
}

warn() {
  echo "UYARI: $*"
  log WARN "$*"
}

error() {
  echo "HATA: $*" >&2
  log ERROR "$*"
}

on_error() {
  local exit_code="$1"
  local line_no="$2"
  local command="$3"
  error "Script hatasi. satir=${line_no} komut=${command} cikis=${exit_code}"
}

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

check_tmux() {
  command -v tmux >/dev/null 2>&1 || { error "tmux bulunamadi"; exit 1; }
}

check_codex() {
  command -v codex >/dev/null 2>&1 || { error "codex bulunamadi"; exit 1; }
}

resolve_base_dir() {
  local candidate
  for candidate in "${BASE_DIR_CANDIDATES[@]}"; do
    if [ -d "$candidate" ]; then
      BASE_DIR="$candidate"
      log INFO "Proje dizini secildi: $BASE_DIR"
      return 0
    fi
  done

  error "Proje klasoru bulunamadi. Beklenen dizinlerden biri yok: ${BASE_DIR_CANDIDATES[*]}"
  exit 1
}

sanitize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g'
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
  printf '%s' "$PROJECT_NAME" > "$CURRENT_PROJECT_FILE"
  log INFO "Aktif proje kaydedildi: $PROJECT_NAME"
}

load_current_project() {
  if [ -f "$CURRENT_PROJECT_FILE" ]; then
    local saved
    saved="$(cat "$CURRENT_PROJECT_FILE" 2>/dev/null || true)"
    if [ -n "${saved:-}" ] && [ -d "${BASE_DIR}/${saved}" ]; then
      set_project_context "$saved"
      log INFO "Kayitli proje yuklendi: $saved"
      return 0
    fi
    log WARN "Kayitli proje gecersiz veya dizin bulunamadi: ${saved:-bos}"
  fi
  return 1
}

ensure_project_selected() {
  if [ -z "${PROJECT_NAME:-}" ] || [ -z "${PROJECT_DIR:-}" ]; then
    warn "Once bir proje sec"
    return 1
  fi
  if [ ! -d "$PROJECT_DIR" ]; then
    error "Proje klasoru bulunamadi: $PROJECT_DIR"
    return 1
  fi
  return 0
}

print_separator() {
  printf '%s\n' "------------------------------------------------------------"
}

print_header() {
  clear
  print_separator
  echo "Codex Tmux Manager"
  print_separator
  echo "Proje kaynagi : ${BASE_DIR:-belirlenmedi}"
  echo "Aktif proje   : ${PROJECT_NAME:-secilmedi}"
  echo "Proje klasoru : ${PROJECT_DIR:-yok}"
  echo "Session       : ${SESSION:-yok}"
  if [ -n "${PROJECT_NAME:-}" ] && session_exists; then
    echo "Oturum        : aktif"
  else
    echo "Oturum        : kapali"
  fi
  if auto_sender_running; then
    echo "Auto sender   : aktif (pid: $(cat "$AUTO_PID_FILE"))"
  else
    echo "Auto sender   : kapali"
  fi
  echo "Log dosyasi   : $LOG_FILE"
  print_separator
}

pause_screen() {
  echo
  read -r -p "Devam icin Enter..."
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

list_projects_array() {
  resolve_base_dir
  mapfile -t PROJECTS < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  log INFO "Proje listesi yenilendi. adet=${#PROJECTS[@]}"
}

render_project_list() {
  local i=1
  echo "Bulunan projeler:"
  echo
  for project in "${PROJECTS[@]}"; do
    printf '  %2d) %s\n' "$i" "$project"
    i=$((i + 1))
  done
}

choose_project() {
  list_projects_array

  if [ "${#PROJECTS[@]}" -eq 0 ]; then
    warn "Hic proje klasoru bulunamadi"
    return 1
  fi

  while true; do
    print_header
    render_project_list
    echo
    echo "Secmek istedigin projeyi numarayla gir."
    local choice
    choice="$(prompt_input "Secim")"

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#PROJECTS[@]}" ]; then
      set_project_context "${PROJECTS[$((choice - 1))]}"
      save_current_project
      info "Aktif proje secildi: $PROJECT_NAME"
      return 0
    fi

    warn "Gecersiz secim: ${choice:-bos}"
    pause_screen
  done
}

check_project_files() {
  ensure_project_selected || return

  local todo="yok"
  local changelog="yok"

  [ -f "$PROJECT_DIR/todo.md" ] && todo="var"
  [ -f "$PROJECT_DIR/CHANGELOG.md" ] && changelog="var"

  echo "todo.md       : $todo"
  echo "CHANGELOG.md  : $changelog"
}

session_exists() {
  ensure_project_selected >/dev/null 2>&1 || return 1
  tmux has-session -t "$SESSION" 2>/dev/null
}

ensure_session() {
  check_tmux
  ensure_project_selected || return 1
  if ! session_exists; then
    warn "Oturum bulunamadi: $SESSION"
    return 1
  fi
  return 0
}

save_last_prompt() {
  printf '%s' "$1" > "$LAST_PROMPT_FILE"
  log INFO "Son prompt kaydedildi: $LAST_PROMPT_FILE"
}

save_draft_prompt() {
  printf '%s' "$1" > "$DRAFT_PROMPT_FILE"
  log INFO "Taslak prompt kaydedildi: $DRAFT_PROMPT_FILE"
}

load_last_prompt() {
  [ -f "$LAST_PROMPT_FILE" ] || return 1
  cat "$LAST_PROMPT_FILE"
}

load_draft_prompt() {
  [ -f "$DRAFT_PROMPT_FILE" ] || return 1
  cat "$DRAFT_PROMPT_FILE"
}

pane_snapshot() {
  tmux capture-pane -t "$SESSION" -pS -80 2>/dev/null || true
}

send_enter() {
  tmux send-keys -t "$SESSION" Enter
}

send_prompt_core() {
  local prompt="$1"

  ensure_session || return 1
  [ -n "${prompt:-}" ] || { warn "Prompt bos olamaz"; return 1; }

  save_last_prompt "$prompt"
  log INFO "Prompt gonderiliyor. uzunluk=${#prompt}"

  tmux send-keys -t "$SESSION" Escape
  sleep 0.15
  tmux set-buffer -- "$prompt"
  tmux paste-buffer -t "$SESSION"
  sleep 0.20
  send_enter
  sleep 0.30

  info "Prompt gonderildi"
}

log_change_summary() {
  ensure_project_selected >/dev/null 2>&1 || return 0

  if ! command -v git >/dev/null 2>&1; then
    log WARN "Git bulunamadi, degisiklik ozeti loglanamadi"
    return 0
  fi

  if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log INFO "Git deposu degil, degisiklik ozeti atlandi"
    return 0
  fi

  local status_output
  local diff_stat

  status_output="$(git -C "$PROJECT_DIR" status --short 2>/dev/null || true)"
  diff_stat="$(git -C "$PROJECT_DIR" diff --stat 2>/dev/null || true)"

  if [ -z "${status_output:-}" ] && [ -z "${diff_stat:-}" ]; then
    log INFO "Kod degisikligi ozeti: calisma dizininde degisiklik yok"
    return 0
  fi

  log INFO "Kod degisikligi ozeti basladi"
  if [ -n "${status_output:-}" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && log INFO "git status: $line"
    done <<< "$status_output"
  fi
  if [ -n "${diff_stat:-}" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && log INFO "git diff --stat: $line"
    done <<< "$diff_stat"
  fi
  log INFO "Kod degisikligi ozeti bitti"
}

start_session() {
  check_tmux
  check_codex
  ensure_project_selected || return

  if session_exists; then
    info "Oturum zaten var: $SESSION"
  else
    tmux new-session -d -s "$SESSION" "cd \"$PROJECT_DIR\" && codex"
    log INFO "Yeni tmux oturumu baslatildi: $SESSION"
    info "Oturum baslatildi: $SESSION"
    sleep 1
  fi
}

save_default_prompt_draft() {
  ensure_project_selected || return
  save_draft_prompt "$DEFAULT_PROMPT"
  info "Varsayilan prompt taslak olarak kaydedildi"
}

read_multiline_prompt() {
  local line
  local prompt=""

  echo "Promptu yaz. Bitirmek icin bos satira bas."
  echo

  while IFS= read -r line; do
    [ -z "$line" ] && break
    if [ -n "$prompt" ]; then
      prompt+=$'\n'
    fi
    prompt+="$line"
  done

  printf '%s' "$prompt"
}

save_custom_prompt_draft() {
  ensure_project_selected || return
  local prompt
  prompt="$(read_multiline_prompt)"

  if [ -z "${prompt:-}" ]; then
    warn "Prompt girilmedi, islem iptal edildi"
    return
  fi

  save_draft_prompt "$prompt"
  info "Ozel prompt taslak olarak kaydedildi"
}

send_draft_prompt() {
  ensure_session || return

  if ! [ -f "$DRAFT_PROMPT_FILE" ]; then
    warn "Kayitli taslak prompt yok"
    return
  fi

  local prompt
  prompt="$(load_draft_prompt)"
  [ -n "${prompt:-}" ] || { warn "Kayitli taslak prompt bos"; return; }

  log INFO "Taslak prompt gonderiliyor"
  send_prompt_core "$prompt"
  log_change_summary
}

send_last_prompt() {
  ensure_session || return

  if ! [ -f "$LAST_PROMPT_FILE" ]; then
    warn "Kayitli son prompt yok"
    return
  fi

  local prompt
  prompt="$(load_last_prompt)"
  [ -n "${prompt:-}" ] || { warn "Kayitli prompt bos"; return; }

  log INFO "Son gonderilen prompt yeniden gonderiliyor"
  send_prompt_core "$prompt"
  log_change_summary
}

enable_full_permissions() {
  ensure_session || return
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

send_status_command() {
  ensure_session || return
  log INFO "/status komutu gonderiliyor"
  tmux send-keys -t "$SESSION" Escape
  sleep 0.15
  tmux send-keys -t "$SESSION" "/status"
  sleep 0.15
  send_enter
  info "/status gonderildi"
}

auto_sender_running() {
  if [ -n "${AUTO_PID_FILE:-}" ] && [ -f "$AUTO_PID_FILE" ]; then
    local pid
    pid="$(cat "$AUTO_PID_FILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

start_auto_sender() {
  ensure_session || return

  if ! [ -f "$LAST_PROMPT_FILE" ]; then
    warn "Once bir taslak prompt gonder"
    return
  fi

  if auto_sender_running; then
    warn "Otomatik gonderici zaten calisiyor"
    return
  fi

  local count
  local minutes
  local interval
  local prompt
  local start_mode

  prompt="$(load_last_prompt)"

  count="$(prompt_input "Kac kere gondersin")"
  [[ "$count" =~ ^[0-9]+$ ]] || { warn "Gecersiz adet"; return; }
  [ "$count" -gt 0 ] || { warn "Adet 0'dan buyuk olmali"; return; }

  minutes="$(prompt_input "Kac dakikada bir gondersin")"
  [[ "$minutes" =~ ^[0-9]+([.][0-9]+)?$ ]] || { warn "Gecersiz dakika"; return; }

  interval="$(awk "BEGIN { printf \"%d\", ($minutes * 60) }")"
  [ "$interval" -gt 0 ] || { warn "Sure 0'dan buyuk olmali"; return; }

  echo "Ilk gonderim secenegi:"
  echo "  1) Hemen"
  echo "  2) Bekleyip sonra"
  start_mode="$(prompt_input "Secim" "1")"
  [[ "$start_mode" =~ ^[12]$ ]] || { warn "Gecersiz secim"; return; }

  log INFO "Otomatik gonderici baslatiliyor. count=$count minutes=$minutes start_mode=$start_mode"

  (
    local i=1

    if [ "$start_mode" = "2" ]; then
      sleep "$interval"
    fi

    while [ "$i" -le "$count" ]; do
      if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        printf '[%s] [%s] oturum bulunamadi, otomatik gonderici durdu\n' "$(timestamp)" "$PROJECT_NAME" >> "$AUTO_LOG_FILE"
        break
      fi

      tmux send-keys -t "$SESSION" Escape
      sleep 0.15
      tmux set-buffer -- "$prompt"
      tmux paste-buffer -t "$SESSION"
      sleep 0.20
      tmux send-keys -t "$SESSION" Enter

      printf '[%s] [%s] gonderim %s/%s\n' "$(timestamp)" "$PROJECT_NAME" "$i" "$count" >> "$AUTO_LOG_FILE"
      log INFO "Auto sender gonderim yapti: $i/$count"
      log_change_summary

      if [ "$i" -lt "$count" ]; then
        sleep "$interval"
      fi

      i=$((i + 1))
    done

    rm -f "$AUTO_PID_FILE"
    log INFO "Otomatik gonderici sonlandi"
  ) >/dev/null 2>&1 &

  echo $! > "$AUTO_PID_FILE"
  info "Otomatik gonderici baslatildi"
  echo "Adet         : $count"
  echo "Dakika       : $minutes"
  echo "Auto log     : $AUTO_LOG_FILE"
}

stop_auto_sender() {
  if auto_sender_running; then
    local pid
    pid="$(cat "$AUTO_PID_FILE")"
    kill "$pid" 2>/dev/null || true
    rm -f "$AUTO_PID_FILE"
    log INFO "Otomatik gonderici durduruldu. pid=$pid"
    info "Otomatik gonderici durduruldu"
  else
    warn "Otomatik gonderici calismiyor"
  fi
}

tail_output() {
  ensure_session || return

  local lines
  local start

  lines="$(prompt_input "Kac satir goreyim" "120")"
  [[ "$lines" =~ ^[0-9]+$ ]] || { warn "Gecersiz satir sayisi"; return; }

  start="$(prompt_input "Kac satir geriden baslayayim" "-300")"
  [[ "$start" =~ ^-?[0-9]+$ ]] || { warn "Gecersiz baslangic"; return; }

  log INFO "Pane output okunuyor. start=$start lines=$lines"
  tmux capture-pane -t "$SESSION" -pS "$start" | tail -n "$lines"
  log_change_summary
}

show_last_prompt() {
  ensure_project_selected || return

  if [ -f "$LAST_PROMPT_FILE" ]; then
    log INFO "Son prompt gosterildi"
    echo "Son prompt:"
    print_separator
    cat "$LAST_PROMPT_FILE"
    print_separator
  else
    warn "Kayitli son prompt yok"
  fi
}

show_draft_prompt() {
  ensure_project_selected || return

  if [ -f "$DRAFT_PROMPT_FILE" ]; then
    log INFO "Taslak prompt gosterildi"
    echo "Taslak prompt:"
    print_separator
    cat "$DRAFT_PROMPT_FILE"
    print_separator
  else
    warn "Kayitli taslak prompt yok"
  fi
}

show_debug_snapshot() {
  ensure_session || return
  log INFO "Debug snapshot istendi"
  echo "Son pane goruntusu:"
  print_separator
  pane_snapshot | tail -n 40
  print_separator
  log_change_summary
}

attach_session() {
  ensure_session || return
  log INFO "Tmux oturumuna baglaniliyor: $SESSION"
  tmux attach -t "$SESSION"
}

list_sessions() {
  check_tmux
  log INFO "Tmux oturum listesi gosterildi"
  tmux ls || true
}

stop_session() {
  check_tmux
  ensure_project_selected || return
  stop_auto_sender >/dev/null 2>&1 || true

  if ! session_exists; then
    warn "Oturum zaten yok: $SESSION"
    return
  fi

  tmux kill-session -t "$SESSION"
  log INFO "Tmux oturumu kapatildi: $SESSION"
  log_change_summary
  info "Oturum kapatildi: $SESSION"
}

bootstrap_project() {
  resolve_base_dir
  if ! load_current_project; then
    log INFO "Kayitli proje bulunamadi, ilk acilista proje secimi istenecek"
    choose_project
  fi
}

show_menu() {
  print_header
  check_project_files || true
  echo
  echo "1) Proje sec"
  echo "2) Oturumu baslat"
  echo "3) Varsayilan promptu taslak kaydet"
  echo "4) Ozel promptu taslak kaydet"
  echo "5) Taslak promptu gonder"
  echo "6) Full access sec"
  echo "7) /status gonder"
  echo "8) Son gonderilen promptu yeniden gonder"
  echo "9) Son gonderilen promptu goster"
  echo "10) Taslak promptu goster"
  echo "11) Son promptu otomatik gonder"
  echo "12) Otomatik gondericiyi iptal et"
  echo "13) Son ciktiyi oku"
  echo "14) Debug snapshot gor"
  echo "15) Oturuma baglan"
  echo "16) Oturumlari listele"
  echo "17) Oturumu kapat"
  echo "18) Cikis"
  echo
}

bootstrap_project
info "Script basladi"

while true; do
  show_menu
  CHOICE="$(prompt_input "Secim")"
  log INFO "Menu secimi alindi: ${CHOICE:-bos}"

  case "$CHOICE" in
    1) choose_project ;;
    2) start_session ;;
    3) save_default_prompt_draft ;;
    4) save_custom_prompt_draft ;;
    5) send_draft_prompt ;;
    6) enable_full_permissions ;;
    7) send_status_command ;;
    8) send_last_prompt ;;
    9) show_last_prompt ;;
    10) show_draft_prompt ;;
    11) start_auto_sender ;;
    12) stop_auto_sender ;;
    13) tail_output ;;
    14) show_debug_snapshot ;;
    15) attach_session ;;
    16) list_sessions ;;
    17) stop_session ;;
    18)
      info "Script kapatiliyor"
      exit 0
      ;;
    *)
      warn "Gecersiz secim"
      ;;
  esac

  pause_screen
done
