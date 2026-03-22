#!/usr/bin/env bash
set -Eeuo pipefail

START_DIR="$(pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

DRY_RUN=0
USE_COMPOSE=0
NO_BUILD=0
AUTO_STASH=1
STASH_CREATED=0
STASH_REF=""
COMMIT_CREATED=0

timestamp() {
  date -Is
}

log() {
  local line
  line="[$(timestamp)] $*"
  printf '%s\n' "$line"
  if [ -n "${LOGFILE:-}" ]; then
    printf '%s\n' "$line" >>"$LOGFILE"
  fi
}

fail() {
  log "ERROR: $*"
  exit 1
}

run() {
  log "RUN: $*"
  if [ "$DRY_RUN" -eq 0 ]; then
    "$@"
  fi
}

is_worktree_dirty() {
  ! git -C "$REPO" diff --quiet || \
  ! git -C "$REPO" diff --cached --quiet || \
  [ -n "$(git -C "$REPO" ls-files --others --exclude-standard)" ]
}

make_commit_message() {
  date -u '+chore: sync update %F %T UTC'
}

create_autostash() {
  [ "$AUTO_STASH" -eq 1 ] || fail "local degisiklikler var. otomatik stash kapali"
  [ "$DRY_RUN" -eq 0 ] || {
    log "DRY-RUN: dirty worktree stash edilecek"
    STASH_CREATED=1
    STASH_REF="DRY_RUN"
    return 0
  }

  local before after stash_msg
  before="$(git -C "$REPO" stash list | head -n 1 || true)"
  stash_msg="update.sh autostash $(timestamp)"
  log "local degisiklikler stash ediliyor"
  git -C "$REPO" stash push --include-untracked -m "$stash_msg" >/dev/null
  after="$(git -C "$REPO" stash list | head -n 1 || true)"

  if [ "$before" = "$after" ] || [ -z "$after" ]; then
    fail "otomatik stash olusturulamadi"
  fi

  STASH_CREATED=1
  STASH_REF="${after%%:*}"
  log "stash created: $STASH_REF"
}

restore_autostash() {
  [ "$STASH_CREATED" -eq 1 ] || return 0
  [ "$DRY_RUN" -eq 0 ] || {
    log "DRY-RUN: stash geri alinacak"
    return 0
  }

  log "stash geri aliniyor: $STASH_REF"
  if git -C "$REPO" stash pop --index >/dev/null; then
    log "stash geri alindi"
    STASH_CREATED=0
    STASH_REF=""
    return 0
  fi

  log "WARN: stash otomatik geri alinamadi. elle incele: git -C $REPO stash list"
  fail "stash pop sirasinda conflict olustu"
}

commit_local_changes() {
  is_worktree_dirty || {
    log "commit skipped: degisiklik yok"
    return 0
  }

  local commit_message
  commit_message="$(make_commit_message)"

  if [ "$DRY_RUN" -eq 0 ]; then
    log "local degisiklikler stage ediliyor"
    git -C "$REPO" add -A
    log "commit olusturuluyor: $commit_message"
    git -C "$REPO" commit -m "$commit_message"
  else
    log "DRY-RUN: local degisiklikler stage edilecek"
    log "DRY-RUN: commit olusturulacak: $commit_message"
  fi

  COMMIT_CREATED=1
}

detect_repo() {
  REPO="$(git -C "$START_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$REPO" ] || fail "bu klasor veya ust klasorleri bir git repository degil: $START_DIR"
}

detect_remote() {
  local remotes
  remotes="$(git -C "$REPO" remote)"
  set -- $remotes
  REMOTE="${1:-}"
  [ -n "$REMOTE" ] || fail "remote bulunamadi"
}

maybe_compose() {
  [ "$USE_COMPOSE" -eq 1 ] || return 0

  if ! command -v docker >/dev/null 2>&1; then
    fail "docker bulunamadi. compose adimi icin docker gerekli"
  fi

  if [ ! -f "$REPO/docker-compose.yml" ] && [ ! -f "$REPO/docker-compose.yaml" ] && \
     [ ! -f "$REPO/compose.yml" ] && [ ! -f "$REPO/compose.yaml" ]; then
    log "compose dosyasi yok, docker skipped"
    return 0
  fi

  if [ "$NO_BUILD" -eq 1 ]; then
    run docker compose -f "${COMPOSE_FILE}" up -d
  else
    run docker compose -f "${COMPOSE_FILE}" up -d --build
  fi

  run docker compose -f "${COMPOSE_FILE}" ps
}

select_compose_file() {
  for candidate in \
    "$REPO/docker-compose.yml" \
    "$REPO/docker-compose.yaml" \
    "$REPO/compose.yml" \
    "$REPO/compose.yaml"
  do
    if [ -f "$candidate" ]; then
      COMPOSE_FILE="$candidate"
      return 0
    fi
  done

  COMPOSE_FILE=""
}

on_error() {
  local exit_code="$?"
  local line_no="${1:-unknown}"
  log "ERROR: satir=$line_no exit_code=$exit_code"
  exit "$exit_code"
}

trap 'on_error $LINENO' ERR

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --compose)
      USE_COMPOSE=1
      ;;
    --no-build)
      NO_BUILD=1
      ;;
    --no-stash)
      AUTO_STASH=0
      ;;
    *)
      fail "bilinmeyen arguman: $1"
      ;;
  esac
  shift
done

detect_repo

LOGDIR="$REPO/.git/update-logs"
LOGFILE="$LOGDIR/update_$(date +%F).log"
mkdir -p "$LOGDIR"
select_compose_file

log "update start"
log "user=$(id -un) host=$(hostname)"
log "repo=$REPO"
log "start_dir=$START_DIR"
log "dry_run=$DRY_RUN compose=$USE_COMPOSE no_build=$NO_BUILD auto_stash=$AUTO_STASH"

git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "burasi bir git repository degil"

log "git fetch"
run git -C "$REPO" fetch --all --prune

BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || fail "detached HEAD durumunda. once branch'e gec"

UPSTREAM="$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$UPSTREAM" ]; then
  detect_remote
  UPSTREAM="$REMOTE/$BRANCH"
else
  REMOTE="${UPSTREAM%%/*}"
fi

log "branch=$BRANCH upstream=$UPSTREAM remote=$REMOTE"
printf '\n'
git -C "$REPO" status -sb

if git -C "$REPO" show-ref --verify --quiet "refs/remotes/$UPSTREAM"; then
  AHEAD_BEHIND="$(git -C "$REPO" rev-list --left-right --count "$UPSTREAM...HEAD" 2>/dev/null || printf '0 0')"
  read -r BEHIND AHEAD <<EOF
$AHEAD_BEHIND
EOF
else
  BEHIND=0
  AHEAD=0
fi

NEED_PULL=0
NEED_PUSH=0
if [ "${AHEAD:-0}" -gt 0 ]; then
  NEED_PUSH=1
fi
if [ "${BEHIND:-0}" -gt 0 ]; then
  NEED_PULL=1
fi

log "need_pull=$NEED_PULL need_push=$NEED_PUSH ahead=${AHEAD:-0} behind=${BEHIND:-0}"

DIRTY=0
if is_worktree_dirty; then
  DIRTY=1
  log "worktree=dirty"
else
  log "worktree=clean"
fi

if ! git -C "$REPO" show-ref --verify --quiet "refs/remotes/$UPSTREAM"; then
  log "upstream yok: first push akisi"
  commit_local_changes
  log "first push"
  run git -C "$REPO" push -u "$REMOTE" "$BRANCH"
elif [ "$NEED_PULL" -eq 1 ] && [ "$NEED_PUSH" -eq 1 ]; then
  fail "branch diverged durumda (ahead=$AHEAD behind=$BEHIND). otomatik merge/rebase yapilmadi"
else
  if [ "$NEED_PULL" -eq 1 ]; then
    if [ "$DIRTY" -eq 1 ]; then
      create_autostash
    fi
    log "pull"
    run git -C "$REPO" pull --ff-only "$REMOTE" "$BRANCH"
    if [ "$STASH_CREATED" -eq 1 ]; then
      restore_autostash
    fi
  fi

  commit_local_changes

  if [ "$NEED_PUSH" -eq 1 ] || [ "$COMMIT_CREATED" -eq 1 ]; then
    if [ "$DIRTY" -eq 1 ] && [ "$NEED_PULL" -eq 0 ]; then
      log "worktree dirty idi; commit sonrasi push yapiliyor"
    fi
    log "push"
    run git -C "$REPO" push "$REMOTE" "$BRANCH"
  else
    log "already synced"
  fi
fi

maybe_compose
log "update done"
