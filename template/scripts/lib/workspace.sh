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

# ------------------------------------------------------------------------------
# Tasks
# ------------------------------------------------------------------------------

# ws_task_branch TASK - the branch every worktree in tasks/TASK has checked out.
# The folder name cannot be turned back into a branch: feat-login may be
# feat/login or feat-login.
ws_task_branch() {
  local task=$1 dir d b found=
  dir=$(ws_task_dir "$task")
  if [ ! -d "$dir" ]; then
    die 3 "no such task: tasks/$task"
  fi
  for d in "$dir"/*/; do
    [ -e "${d}.git" ] || continue
    b=$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null) || continue
    if [ -z "$found" ]; then
      found=$b
    elif [ "$b" != "$found" ]; then
      die 4 "tasks/$task mixes branches: $found and $b"
    fi
  done
  if [ -z "$found" ]; then
    die 3 "tasks/$task has no worktrees to read its branch from" \
          "name the branch instead: scripts/task-create <branch> <repo>..."
  fi
  printf '%s\n' "$found"
}

# ws_write_task_files TASK BRANCH - the task folder, its CLAUDE.md, NOTES.md and
# .claude/plans/. Existing files are left alone, so a re-run never clobbers
# notes. CLAUDE.md lists no repositories, so task-add cannot make it stale.
ws_write_task_files() {
  local task=$1 branch=$2 dir
  dir=$(ws_task_dir "$task")
  mkdir -p "$dir/.claude/plans"

  if [ ! -e "$dir/CLAUDE.md" ]; then
    cat > "$dir/CLAUDE.md" <<EOT
# Task: $task

Branch \`$branch\` in every repository below. Each subfolder is a git
worktree of \`repos/<name>.git\`; open one PR per repository, all from this
branch.

- Notes: \`NOTES.md\`
- Plans: \`.claude/plans/\` (links)
- Cross-task notes: \`../../docs/\`

Workspace rules: \`../../CLAUDE.md\`.
EOT
    log_info "wrote    $(ws_rel "$dir/CLAUDE.md")"
  fi

  if [ ! -e "$dir/NOTES.md" ]; then
    cat > "$dir/NOTES.md" <<EOT
# $task

Branch: \`$branch\`
EOT
    log_info "wrote    $(ws_rel "$dir/NOTES.md")"
  fi
}

# ws_wt_preflight TASK REPO BRANCH BASE - check one worktree before anything is
# created, so a multi-repo task fails up front instead of half-made. Prints
# "exists" or "create"; dies otherwise. BASE may be empty when the branch
# already exists.
ws_wt_preflight() {
  local task=$1 repo=$2 branch=$3 base=$4 dir wt p b f checked_out

  dir=$(ws_repo_dir "$repo")
  wt=$(ws_wt_path "$task" "$repo")

  # A stale record left by a hand-deleted directory is the most common
  # confusing failure here, and clearing it costs nothing.
  git -C "$dir" worktree prune

  while IFS=$'\t' read -r p b f; do
    [ -n "$p" ] || continue
    if [ "$p" = "$wt" ] ||
       { [ -d "$p" ] && [ -d "$wt" ] && [ "$(ws_realpath "$p")" = "$(ws_realpath "$wt")" ]; }; then
      if [ "$b" = "$branch" ]; then
        printf 'exists\n'
        return 0
      fi
      die 4 "$(ws_rel "$wt") is already the worktree for '${b:-a detached HEAD}'" \
            "two branch names can sanitize to one task folder; rename one of them"
    fi
  done <<EOT
$(ws_worktree_records "$dir")
EOT

  if [ -e "$wt" ]; then
    # rmdir refuses a non-empty directory, which is exactly the guard we want.
    # These scripts never run rm -rf.
    rmdir "$wt" 2>/dev/null ||
      die 4 "$(ws_rel "$wt") already exists and is not a worktree of $repo" \
            "move it out of the way, then re-run"
  fi

  checked_out=$(ws_branch_worktree "$dir" "$branch") || checked_out=
  if [ -n "$checked_out" ]; then
    die 4 "branch '$branch' of $repo is already checked out at $(ws_rel "$checked_out")"
  fi

  if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch" ||
     git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    printf 'create\n'
    return 0
  fi

  if ws_is_env_branch "$branch" "$dir"; then
    die 3 "env branch '$branch' does not exist in $repo, locally or on origin" \
          "env tasks check out existing branches; they never create one"
  fi

  if [ -z "$base" ]; then
    die 3 "cannot determine a base branch for '$repo'" \
          "pass --base <ref>, or set one:" \
          "  git -C repos/$repo.git config workflow.baseBranch main"
  fi
  if ! git -C "$dir" rev-parse --verify --quiet "$(ws_base_ref "$dir" "$base")^{commit}" >/dev/null; then
    die 3 "base '$base' does not exist in $repo"
  fi
  printf 'create\n'
}

# ws_wt_create TASK REPO BRANCH BASE - add tasks/TASK/REPO on BRANCH. Assumes
# ws_wt_preflight said "create".
ws_wt_create() {
  local task=$1 repo=$2 branch=$3 base=$4 dir wt base_ref old new
  local local_exists=0 remote_exists=0

  dir=$(ws_repo_dir "$repo")
  wt=$(ws_wt_path "$task" "$repo")

  if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
    local_exists=1
  fi
  if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    remote_exists=1
  fi

  mkdir -p "$(dirname -- "$wt")"

  if [ "$local_exists" = 1 ]; then
    if [ "$remote_exists" = 1 ]; then
      # Fetches move origin/* but never refs/heads/*, so a local branch that
      # is merely behind would start the worktree stale. The old value makes
      # update-ref refuse if the branch moved meanwhile.
      old=$(git -C "$dir" rev-parse "refs/heads/$branch")
      new=$(git -C "$dir" rev-parse "refs/remotes/origin/$branch")
      if [ "$old" != "$new" ] && git -C "$dir" merge-base --is-ancestor "$old" "$new"; then
        git -C "$dir" update-ref "refs/heads/$branch" "$new" "$old"
        log_info "ff       $branch to origin/$branch"
      fi
      if ws_is_env_branch "$branch" "$dir" &&
         [ -z "$(git -C "$dir" for-each-ref --format='%(upstream)' "refs/heads/$branch")" ]; then
        git -C "$dir" branch -q --set-upstream-to="origin/$branch" "$branch"
      fi
    fi
    log_info "start    existing local branch $branch"
    git -C "$dir" worktree add "$wt" "$branch" >/dev/null
  elif [ "$remote_exists" = 1 ]; then
    log_info "start    origin/$branch"
    git -C "$dir" worktree add --track -b "$branch" "$wt" "origin/$branch" >/dev/null
  else
    base_ref=$(ws_base_ref "$dir" "$base")
    log_info "base     $base_ref"
    # --no-track: branching from origin/<base> would otherwise make <base> the
    # upstream, which breaks `git push` defaults and makes a new branch look
    # merged. The upstream arrives with the first `git push -u origin <branch>`.
    git -C "$dir" worktree add --no-track -b "$branch" "$wt" "$base_ref" >/dev/null
  fi

  log_info "path     $(ws_rel "$wt")"
}

# ws_copy_shared REPO WORKTREE - copy shared/REPO/ into the worktree, keeping
# relative paths and never overwriting. Warn about a copied path the worktree
# does not ignore: it would make the worktree dirty and block a retire.
ws_copy_shared() {
  local repo=$1 wt=$2 src f rel
  src=$SHARED_DIR/$repo
  if [ ! -d "$src" ]; then
    return 0
  fi
  while IFS= read -r -d '' f; do
    rel=${f#"$src"/}
    if [ -e "$wt/$rel" ] || [ -L "$wt/$rel" ]; then
      log_detail "skip $rel (already present)"
      continue
    fi
    mkdir -p "$wt/$(dirname -- "$rel")"
    if [ -L "$f" ]; then
      ln -s "$(readlink -- "$f")" "$wt/$rel"
    else
      cp -p "$f" "$wt/$rel"
    fi
    log_info "copied   shared/$repo/$rel"
    if ! git -C "$wt" check-ignore -q -- "$rel" 2>/dev/null; then
      log_warn "$rel is not ignored in $repo; the worktree will show it as untracked"
      log_detail "ignore it in $repo, or remove shared/$repo/$rel"
    fi
  done < <(find "$src" \( -type f -o -type l \) -print0)
}

# ws_list_tasks - one task folder name per line, sorted.
ws_list_tasks() {
  local d
  if [ ! -d "$TASKS_DIR" ]; then
    return 0
  fi
  for d in "$TASKS_DIR"/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    printf '%s\n' "${d##*/}"
  done
}

# ws_task_from_pwd - the task holding the current directory, or return 1.
ws_task_from_pwd() {
  local cur rel
  cur=$(ws_realpath "$PWD")
  case $cur in
    "$TASKS_DIR"/*)
      rel=${cur#"$TASKS_DIR"/}
      printf '%s\n' "${rel%%/*}"
      ;;
    *)
      return 1
      ;;
  esac
}

# ws_task_worktrees TASK - repo<TAB>path<TAB>branch<TAB>flags for every
# worktree registered under tasks/TASK/. Read from git's records rather than
# the directory, so a locked or missing worktree is still seen.
ws_task_worktrees() {
  local task=$1 repo dir p b f prefix
  prefix=$(ws_task_dir "$task")/
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    dir=$REPOS_DIR/$repo.git
    while IFS=$'\t' read -r p b f; do
      case $p in
        "$prefix"*) printf '%s\t%s\t%s\t%s\n' "$repo" "$p" "$b" "$f" ;;
      esac
    done <<EOT
$(ws_worktree_records "$dir")
EOT
  done <<EOT
$(ws_list_repos)
EOT
}

# ------------------------------------------------------------------------------
# Landing
# ------------------------------------------------------------------------------

# ws_landed REPO_DIR BRANCH [PR_STATE] - verdict<TAB>evidence, where verdict is
# merged, gone, new or open. A task has landed when every repository says
# merged or gone.
ws_landed() {
  local dir=$1 b=$2 pr_state=${3:-} base base_ref line upstream track

  if [ "$pr_state" = MERGED ]; then
    printf 'merged\tpull request\n'
    return 0
  fi

  line=$(ws_branch_table "$dir" | awk -F'\t' -v n="$b" '$1 == n { print; exit }')
  upstream=$(printf '%s' "$line" | cut -f2)
  track=$(printf '%s' "$line" | cut -f3)

  base=$(ws_default_branch "$dir" 2>/dev/null) || base=
  base_ref=
  if [ -n "$base" ]; then
    base_ref=$(ws_base_ref "$dir" "$base")
  fi

  # A branch with no upstream and no commits beyond the base was never worked
  # on. git calls it merged, and keeps doing so as the base moves on, but
  # retiring a fresh task would be a nasty surprise. The upstream test
  # matters: a pushed branch that was fast-forward merged has landed.
  if [ -z "$upstream" ] && [ -n "$base_ref" ] &&
     git -C "$dir" merge-base --is-ancestor "refs/heads/$b" "$base_ref" 2>/dev/null; then
    printf 'new\tno commits yet\n'
    return 0
  fi

  if [ -n "$base_ref" ] && [ "$b" != "$base" ] &&
     git -C "$dir" merge-base --is-ancestor "refs/heads/$b" "$base_ref" 2>/dev/null; then
    printf 'merged\tmerged into %s\n' "$base"
    return 0
  fi

  case $track in
    *gone*)
      printf 'gone\tremote branch deleted\n'
      return 0
      ;;
  esac

  printf 'open\t-\n'
}
