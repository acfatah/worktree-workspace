#!/usr/bin/env bash

# ==============================================================================
# Shared helpers for the workspace scripts.
#
# The workspace root is derived from this file's own location, not from the
# current directory: the scripts are invoked from inside task worktrees, from
# repos/, and from outside the workspace entirely, and an upward walk guesses
# wrong in all three cases. Set WORKSPACE_ROOT to override.
# ==============================================================================

_ws_lib_dir=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./log.sh
. "$_ws_lib_dir/log.sh"

# Not every script uses every directory.
# shellcheck disable=SC2034
{
  WORKSPACE_ROOT=${WORKSPACE_ROOT:-$(cd -P "$_ws_lib_dir/../.." && pwd)}
  REPOS_DIR=$WORKSPACE_ROOT/repos
  TASKS_DIR=$WORKSPACE_ROOT/tasks
  ARCHIVE_DIR=$WORKSPACE_ROOT/archive
  SHARED_DIR=$WORKSPACE_ROOT/shared
  DOCS_DIR=$WORKSPACE_ROOT/docs
  WORKSPACE_CONF=$WORKSPACE_ROOT/workspace.conf
}

export WORKSPACE_ROOT

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# ws_load_conf - source workspace.conf, if present. It is optional and created
# on demand; every key has a default here.
ws_load_conf() {
  if [ -f "$WORKSPACE_CONF" ]; then
    # shellcheck source=/dev/null
    . "$WORKSPACE_CONF"
  fi
  # Space-separated env branches. Empty means "each repo's default branch".
  ENV_BRANCHES=${ENV_BRANCHES:-}
}

ws_load_conf

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------

# ws_require_workspace - refuse to run outside a workspace.
ws_require_workspace() {
  if [ ! -d "$REPOS_DIR" ]; then
    die 2 "no repos/ directory under $WORKSPACE_ROOT" \
          "run these scripts from a workspace, or set WORKSPACE_ROOT"
  fi
}

# ws_realpath PATH - resolve symlinks without GNU readlink -f.
ws_realpath() {
  local p=$1 d
  while [ -L "$p" ]; do
    d=$(cd -P "$(dirname -- "$p")" && pwd)
    p=$(readlink -- "$p")
    case $p in
      /*) ;;
      *)  p=$d/$p ;;
    esac
  done
  if [ -d "$p" ]; then
    (cd -P "$p" && pwd)
  else
    printf '%s/%s\n' "$(cd -P "$(dirname -- "$p")" && pwd)" "$(basename -- "$p")"
  fi
}

# ws_sanitize BRANCH - the branch with every "/" turned into "-".
ws_sanitize() {
  local b=$1
  printf '%s\n' "${b//\//-}"
}

# ws_slug BRANCH - the branch with its scope stripped; the per-branch resource
# name hooks use, such as a database suffix.
ws_slug() {
  local b=$1 s
  s=${b#*/}
  printf '%s\n' "${s//\//-}"
}

# ws_scope BRANCH - the scope prefix, empty when the branch has no slash.
ws_scope() {
  local b=$1
  case $b in
    */*) printf '%s\n' "${b%%/*}" ;;
    *)   printf '\n' ;;
  esac
}

# ws_task_name BRANCH - the task folder name: feat/login is tasks/feat-login.
ws_task_name() {
  ws_sanitize "$1"
}

# ws_task_dir TASK
ws_task_dir() {
  printf '%s\n' "$TASKS_DIR/$1"
}

# ws_wt_path TASK REPO - the task's worktree of REPO.
ws_wt_path() {
  printf '%s\n' "$TASKS_DIR/$1/$2"
}

# ws_rel PATH - path relative to the workspace root, for display.
ws_rel() {
  local p=$1
  case $p in
    "$WORKSPACE_ROOT"/*) printf '%s\n' "${p#"$WORKSPACE_ROOT"/}" ;;
    *)                   printf '%s\n' "$p" ;;
  esac
}

# ------------------------------------------------------------------------------
# Repositories
# ------------------------------------------------------------------------------

# ws_list_repos - one repository name per line, without the .git suffix.
ws_list_repos() {
  local d name
  if [ ! -d "$REPOS_DIR" ]; then
    return 0
  fi
  for d in "$REPOS_DIR"/*.git/; do
    # A bare repository has HEAD at its top level.
    if [ -f "${d}HEAD" ]; then
      name=${d%/}
      name=${name##*/}
      printf '%s\n' "${name%.git}"
    fi
  done
}

# ws_repo_dir NAME - print repos/NAME.git, or die 3 listing what does exist.
ws_repo_dir() {
  local name=$1 known
  if [ -z "$name" ]; then
    die 2 "missing <repo> argument"
  fi
  if [ ! -f "$REPOS_DIR/$name.git/HEAD" ]; then
    known=$(ws_list_repos | tr '\n' ' ')
    die 3 "no such repository: repos/$name.git" \
          "known repositories: ${known:-<none; run scripts/repo-add <url>>}"
  fi
  printf '%s\n' "$REPOS_DIR/$name.git"
}

# ws_infer_repo - the repo implied by the current directory, or the only one.
ws_infer_repo() {
  local cur rel count
  cur=$(ws_realpath "$PWD")
  case $cur in
    "$REPOS_DIR"/*)
      rel=${cur#"$REPOS_DIR"/}
      rel=${rel%%/*}
      printf '%s\n' "${rel%.git}"
      return 0
      ;;
    "$TASKS_DIR"/*/*)
      # tasks/<task>/<repo>/...
      rel=${cur#"$TASKS_DIR"/*/}
      printf '%s\n' "${rel%%/*}"
      return 0
      ;;
  esac
  count=$(ws_list_repos | wc -l | tr -d ' ')
  if [ "$count" = 1 ]; then
    ws_list_repos
    return 0
  fi
  return 1
}

# ws_check_branch BRANCH - reject names git or the shell would misread.
ws_check_branch() {
  local b=$1
  if [ -z "$b" ]; then
    die 2 "missing <branch> argument"
  fi
  case $b in
    -*) die 2 "invalid branch name (leading dash): $b" ;;
  esac
  if ! git check-ref-format "refs/heads/$b" >/dev/null 2>&1; then
    die 2 "invalid branch name: $b"
  fi
}

# ------------------------------------------------------------------------------
# Git state
# ------------------------------------------------------------------------------

# ws_default_branch REPO_DIR - the base branch ladder. Prints a branch name.
ws_default_branch() {
  local dir=$1 b


  b=$(git -C "$dir" config --get workflow.baseBranch 2>/dev/null) || b=
  if [ -n "$b" ]; then printf '%s\n' "$b"; return 0; fi

  b=$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) || b=
  if [ -n "$b" ]; then printf '%s\n' "${b#origin/}"; return 0; fi

  # origin/HEAD is unset in some clones; ask the remote once, then retry.
  git -C "$dir" remote set-head origin --auto >/dev/null 2>&1 || true
  b=$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) || b=
  if [ -n "$b" ]; then printf '%s\n' "${b#origin/}"; return 0; fi

  for b in main master develop; do
    if git -C "$dir" rev-parse --verify --quiet "refs/remotes/origin/$b" >/dev/null 2>&1; then
      printf '%s\n' "$b"
      return 0
    fi
  done

  b=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || b=
  if [ -n "$b" ]; then printf '%s\n' "$b"; return 0; fi

  return 1
}

# ws_is_env_branch BRANCH REPO_DIR - is BRANCH a long-lived env branch (main,
# dev, ...)? ENV_BRANCHES from workspace.conf decides; without it, only the
# repo's default branch is one.
ws_is_env_branch() {
  local branch=$1 dir=$2 b
  if [ -n "$ENV_BRANCHES" ]; then
    for b in $ENV_BRANCHES; do
      if [ "$b" = "$branch" ]; then
        return 0
      fi
    done
    return 1
  fi
  b=$(ws_default_branch "$dir" 2>/dev/null) || return 1
  [ "$b" = "$branch" ]
}

# ws_base_ref REPO_DIR BRANCH - the start point git should branch from.
ws_base_ref() {
  local dir=$1 b=$2
  if git -C "$dir" rev-parse --verify --quiet "refs/remotes/origin/$b" >/dev/null 2>&1; then
    printf '%s\n' "origin/$b"
  else
    printf '%s\n' "$b"
  fi
}

# ws_is_dirty DIR - uncommitted changes, or a merge/rebase/cherry-pick underway.
ws_is_dirty() {
  local dir=$1 p path
  if [ -n "$(git --no-optional-locks -C "$dir" status --porcelain --untracked-files=normal 2>/dev/null)" ]; then
    return 0
  fi
  for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    path=$(git -C "$dir" rev-parse --git-path "$p" 2>/dev/null) || continue
    if [ -e "$path" ]; then
      return 0
    fi
  done
  return 1
}

# ws_unpushed_count DIR - commits not reachable from any origin ref. Correct
# with and without a configured upstream, which "@{u}" is not.
ws_unpushed_count() {
  git -C "$1" rev-list --count HEAD --not --remotes=origin 2>/dev/null || printf '0\n'
}

# ws_branch_table REPO_DIR - branch, upstream, track, worktree path.
#
# Note: %(upstream:track) is empty both when a branch is in sync and when it has
# no upstream at all; %(upstream:short) is what tells those apart. "[gone]" in
# the track field is the deleted-remote-branch signal pruning needs.
ws_branch_table() {
  git -C "$1" for-each-ref \
    --format='%(refname:short)%09%(upstream:short)%09%(upstream:track)%09%(worktreepath)' \
    refs/heads/ 2>/dev/null
}

# ws_worktree_records REPO_DIR - path<TAB>branch<TAB>flags, one per worktree.
ws_worktree_records() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { if (p != "") print p "\t" b "\t" f; p = substr($0, 10); b = ""; f = "" }
    /^branch /   { b = substr($0, 8); sub(/^refs\/heads\//, "", b) }
    /^detached$/ { f = f "detached," }
    /^bare$/     { f = f "bare," }
    /^locked/    { f = f "locked," }
    /^prunable/  { f = f "prunable," }
    END          { if (p != "") print p "\t" b "\t" f }
  '
}

# ws_branch_worktree REPO_DIR BRANCH - the path where BRANCH is checked out.
ws_branch_worktree() {
  local dir=$1 branch=$2
  ws_worktree_records "$dir" | awk -F'\t' -v b="$branch" '$2 == b { print $1; exit }'
}

# ------------------------------------------------------------------------------
# GitHub, always optional
# ------------------------------------------------------------------------------

# ws_gh_ok - is gh usable without a network round trip? `gh auth status` would
# make one; `gh auth token` reads the local keyring.
ws_gh_ok() {
  if [ -n "${WORKFLOW_NO_GH:-}" ]; then
    return 1
  fi
  command -v gh >/dev/null 2>&1 || return 1
  gh auth token >/dev/null 2>&1
}

# ws_pr_table REPO_DIR - branch<TAB>#number<TAB>state for every PR, or nothing.
ws_pr_table() {
  local dir=$1
  if ! ws_gh_ok; then
    return 0
  fi
  ( cd "$dir" && gh pr list --state all --limit 200 \
      --json headRefName,number,state,isDraft \
      --jq '.[] | [.headRefName, "#" + (.number|tostring), (if .isDraft then "DRAFT" else .state end)] | @tsv'
  ) 2>/dev/null || true
}

# ws_pr_state REPO_DIR BRANCH - MERGED, OPEN, CLOSED, DRAFT, or nothing.
ws_pr_state() {
  local dir=$1 branch=$2
  if ! ws_gh_ok; then
    return 0
  fi
  ( cd "$dir" && gh pr view "$branch" --json state,isDraft \
      --jq 'if .isDraft then "DRAFT" else .state end'
  ) 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Lifecycle hooks
# ------------------------------------------------------------------------------

# ws_hook_env EVENT TASK REPO REPO_DIR BRANCH WORKTREE [BASE_BRANCH]
#
# WORKFLOW_REPO_DIR is the bare repository, repos/<repo>.git.
ws_hook_env() {
  WORKFLOW_EVENT=$1
  WORKFLOW_ROOT=$WORKSPACE_ROOT
  WORKFLOW_TASK=$2
  WORKFLOW_TASK_DIR=$(ws_task_dir "$WORKFLOW_TASK")
  WORKFLOW_REPO=$3
  WORKFLOW_REPO_DIR=$4
  WORKFLOW_BRANCH=$5
  WORKFLOW_WORKTREE=$6
  WORKFLOW_BASE_BRANCH=${7:-}
  WORKFLOW_WORKTREE_NAME=$(ws_sanitize "$WORKFLOW_BRANCH")
  WORKFLOW_SCOPE=$(ws_scope "$WORKFLOW_BRANCH")
  WORKFLOW_SLUG=$(ws_slug "$WORKFLOW_BRANCH")
  WORKFLOW_FORCE=${WORKFLOW_FORCE:-0}

  export WORKFLOW_EVENT WORKFLOW_ROOT WORKFLOW_TASK WORKFLOW_TASK_DIR \
         WORKFLOW_REPO WORKFLOW_REPO_DIR WORKFLOW_BRANCH WORKFLOW_WORKTREE \
         WORKFLOW_BASE_BRANCH WORKFLOW_WORKTREE_NAME WORKFLOW_SCOPE \
         WORKFLOW_SLUG WORKFLOW_FORCE
}

# ws_run_hook EVENT - run <worktree>/.workflow/<event>, if it exists.
#
# Hooks come only from the worktree, committed with the branch: a bare
# repository has no files on disk to fall back to. Output is never captured,
# so an interactive psql prompt still works.
ws_run_hook() {
  local event=$1 hook

  if [ -n "${WORKFLOW_NO_HOOKS:-}" ]; then
    return 0
  fi

  hook=$WORKFLOW_WORKTREE/.workflow/$event
  if [ ! -e "$hook" ]; then
    return 0
  fi

  if [ ! -x "$hook" ]; then
    log_warn "$(ws_rel "$hook") exists but is not executable; skipping"
    log_detail "chmod +x $(ws_rel "$hook")"
    return 0
  fi

  log_step "running $(ws_rel "$hook")"
  ( cd "$WORKFLOW_WORKTREE" && exec "$hook" )
}
