#!/usr/bin/env bash

# ==============================================================================
# Logging helpers layered on colors.sh.
#
# Everything here writes to stderr. stdout is reserved for payload, so that
# `cd "$(scripts/task-create feat/login app)"` works and --porcelain output
# stays pipeable.
#
# Source this at a script's top level, never inside a function: colors.sh reads
# "$@" at source time to honour --color / --no-color.
# ==============================================================================

_log_lib_dir=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./colors.sh
. "$_log_lib_dir/colors.sh"

case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*utf-8*|*UTF8*|*utf8*)
    _g_ok='✓'; _g_no='✗'; _g_warn='!'; _g_arrow='→'
    ;;
  *)
    _g_ok='[ok]'; _g_no='[x]'; _g_warn='[!]'; _g_arrow='->'
    ;;
esac

log_step()    { printf '%s %s\n' "$(PC_cyan "$_g_arrow")" "$*" >&2; }
log_info()    { if [ -z "$*" ]; then printf '\n' >&2; else printf '  %s\n' "$*" >&2; fi; }
log_detail()  { printf '  %s\n' "$(PC_dim "$*")" >&2; }
log_success() { printf '%s %s\n' "$(PC_green "$_g_ok")" "$*" >&2; }
log_warn()    { printf '%s %s\n' "$(PC_yellow "$_g_warn")" "$*" >&2; }
log_error()   { printf '%s %s\n' "$(PC_red "$_g_no")" "$*" >&2; }

# die CODE MESSAGE [MESSAGE...] - one log_error per message, then exit CODE.
die() {
  local code=$1 line
  shift
  for line in "$@"; do
    log_error "$line"
  done
  exit "$code"
}

# usage_die [MESSAGE] - complain, print $USAGE, exit 2.
usage_die() {
  if [ $# -gt 0 ]; then
    log_error "$*"
  fi
  printf '%s\n' "${USAGE:-}" >&2
  exit 2
}

# confirm PROMPT [y|n] - 0 for yes, 1 for no. Reads the terminal, not stdin,
# because these scripts get piped and call each other.
confirm() {
  local prompt=$1 default=${2:-n} reply hint

  if [ -n "${WORKFLOW_YES:-}" ]; then
    return 0
  fi

  case $default in
    y) hint='[Y/n]' ;;
    *) hint='[y/N]' ;;
  esac

  # /dev/tty can exist and still be unopenable (cron, CI, a detached process),
  # so probe it in a subshell rather than trusting -r.
  if ! ( : </dev/tty ) 2>/dev/null; then
    log_warn "no terminal available; assuming '$default' for: $prompt"
    [ "$default" = y ]
    return
  fi

  printf '%s %s %s ' "$(PC_yellow '?')" "$prompt" "$(PC_dim "$hint")" >&2
  IFS= read -r reply </dev/tty || reply=''
  if [ -z "$reply" ]; then
    reply=$default
  fi

  case $reply in
    [yY]*) return 0 ;;
    *)     return 1 ;;
  esac
}

# run CMD [ARG...] - echo the command, then run it.
run() {
  log_detail "\$ $*"
  "$@"
}
