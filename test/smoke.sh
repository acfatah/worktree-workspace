#!/usr/bin/env bash
#
# End-to-end smoke test for template/scripts.
#
# Builds throwaway git repositories under a temporary directory and exercises
# every script against them. No network, no dependencies beyond bash and git.
#
#   bash test/smoke.sh [--keep] [--filter <substring>] [--verbose]

set -uo pipefail

REPO_ROOT=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
KEEP=0
FILTER=
VERBOSE=0

while [ $# -gt 0 ]; do
  case $1 in
    --keep)    KEEP=1 ;;
    --filter)  shift; FILTER=${1:-} ;;
    --verbose) VERBOSE=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *)         printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

TEST_ROOT=$(mktemp -d)
if [ "$KEEP" != 1 ]; then
  trap 'rm -rf "$TEST_ROOT"' EXIT
fi

# Isolation: no user config, no real gh, no colour in assertions.
export HOME=$TEST_ROOT
export GIT_CONFIG_GLOBAL=$TEST_ROOT/gitconfig
export GIT_CONFIG_NOSYSTEM=1
export NO_COLOR=1
export WORKFLOW_NO_GH=1
export WORKFLOW_YES=1
unset GIT_DIR GIT_WORK_TREE 2>/dev/null || true

git config --file "$GIT_CONFIG_GLOBAL" user.name "Smoke Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email smoke@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" protocol.file.allow always
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

n=0
failures=0
current=

t() {
  current=$1
  n=$((n + 1))
}

pass() { printf 'ok %d - %s\n' "$n" "$current"; }

fail() {
  printf 'not ok %d - %s\n' "$n" "$current"
  printf '  %s\n' "$@" | sed 's/^/  /'
  failures=$((failures + 1))
}

check() {
  # check DESCRIPTION CONDITION_RESULT [DETAIL...]
  local desc=$1 result=$2
  shift 2
  t "$desc"
  if [ "$result" = 0 ]; then pass; else fail "$@"; fi
}

skip_filtered() {
  case ${1:-} in
    *"$FILTER"*) return 1 ;;
    *) return 0 ;;
  esac
}

if [ "$VERBOSE" = 1 ]; then set -x; fi

# ------------------------------------------------------------------------------
# Fixtures
# ------------------------------------------------------------------------------

make_origin() {
  # make_origin NAME DEFAULT_BRANCH
  local name=$1 branch=$2
  git init --bare -q -b "$branch" "$TEST_ROOT/origin/$name.git"
  git init -q -b "$branch" "$TEST_ROOT/seed-$name"
  (
    cd "$TEST_ROOT/seed-$name"
    printf '%s\n' "$name" > README.md
    printf '.env\n!.env.example\n' > .gitignore
    printf 'KEY=example\n' > .env.example
    git add -A
    git commit -qm "initial commit"
    git remote add origin "$TEST_ROOT/origin/$name.git"
    git push -q -u origin "$branch"
  )
}

make_origin app main
make_origin legacy master

# A second remote branch, to check that repo-add does not keep a stale local
# copy of it.
( cd "$TEST_ROOT/seed-app" && git switch -qc feat/extra && git commit -q --allow-empty -m extra \
    && git push -q origin feat/extra && git switch -q main )

WS=$TEST_ROOT/ws
mkdir -p "$WS"
cp -R "$REPO_ROOT/template/." "$WS/"

wt() { ( cd "$WS" && ./scripts/"$@" ); }

# lib FUNCTION ARGS... - call a workspace.sh helper inside the test workspace.
lib() {
  ( WORKSPACE_ROOT=$WS; . "$WS/scripts/lib/workspace.sh"; "$@" )
}

# ------------------------------------------------------------------------------
# repo-add
# ------------------------------------------------------------------------------

out=$(wt repo-add "file://$TEST_ROOT/origin/app.git" app 2>"$TEST_ROOT/repo-add.err")
rc=$?
APP=$WS/repos/app.git
check "repo-add clones into repos/app.git" \
  "$( [ "$rc" = 0 ] && [ "$out" = "$APP" ]; echo $? )" \
  "rc=$rc out=$out"

bare=$(git -C "$APP" rev-parse --is-bare-repository 2>/dev/null)
check "repo-add makes a bare clone" "$( [ "$bare" = true ]; echo $? )" "bare=$bare"

check "repo-add fetches origin/* refs" \
  "$( git -C "$APP" rev-parse --verify --quiet refs/remotes/origin/main >/dev/null \
      && git -C "$APP" rev-parse --verify --quiet refs/remotes/origin/feat/extra >/dev/null; echo $? )"

head=$(git -C "$APP" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
check "repo-add pins origin/HEAD" "$( [ "$head" = origin/main ]; echo $? )" "origin/HEAD=$head"

locals=$(git -C "$APP" for-each-ref --format='%(refname:short)' refs/heads/ | tr '\n' ' ')
check "repo-add keeps only the default local branch" \
  "$( [ "$locals" = 'main ' ]; echo $? )" "locals=$locals"

up=$(git -C "$APP" for-each-ref --format='%(upstream:short)' refs/heads/main)
check "the default local branch tracks origin" "$( [ "$up" = origin/main ]; echo $? )" "upstream=$up"

check "repo-add creates no worktrees/ directory" "$( [ ! -e "$WS/worktrees/app" ]; echo $? )"

check "repo-add says nothing about skills" \
  "$( ! grep -qi skills "$TEST_ROOT/repo-add.err"; echo $? )" "$(cat "$TEST_ROOT/repo-add.err")"

wt repo-add "file://$TEST_ROOT/origin/app.git" app >/dev/null 2>&1
check "repo-add refuses an existing repo with exit 4" "$( [ $? = 4 ]; echo $? )"

wt repo-add "file://$TEST_ROOT/origin/app.git" 'bad name' >/dev/null 2>&1
check "repo-add refuses a bad name with exit 2" "$( [ $? = 2 ]; echo $? )"

wt repo-add "file://$TEST_ROOT/origin/legacy.git" legacy >/dev/null 2>&1
default=$(lib ws_default_branch "$WS/repos/legacy.git" 2>/dev/null)
check "repo-add detects a master default branch" \
  "$( [ "$default" = master ]; echo $? )" "default=$default"

wt repo-add --branch feat/extra "file://$TEST_ROOT/origin/app.git" app2 >/dev/null 2>&1
base=$(git -C "$WS/repos/app2.git" config --get workflow.baseBranch)
default=$(lib ws_default_branch "$WS/repos/app2.git" 2>/dev/null)
check "repo-add --branch records the base branch" \
  "$( [ "$base" = feat/extra ] && [ "$default" = feat/extra ]; echo $? )" \
  "workflow.baseBranch=$base default=$default"
rm -rf "$WS/repos/app2.git"

# ------------------------------------------------------------------------------
# Library helpers
# ------------------------------------------------------------------------------

repos=$(lib ws_list_repos | tr '\n' ' ')
check "ws_list_repos names bare repos without .git" \
  "$( [ "$repos" = 'app legacy ' ]; echo $? )" "repos=$repos"

check "ws_repo_dir resolves to repos/<name>.git" \
  "$( [ "$(lib ws_repo_dir app 2>/dev/null)" = "$APP" ]; echo $? )"

lib ws_repo_dir nosuch >/dev/null 2>&1
check "ws_repo_dir exits 3 for an unknown repository" "$( [ $? = 3 ]; echo $? )"

task=$(lib ws_task_name feat/login)
check "ws_task_name turns / into -" "$( [ "$task" = feat-login ]; echo $? )" "task=$task"

check "ws_task_dir and ws_wt_path build task paths" \
  "$( [ "$(lib ws_task_dir feat-login)" = "$WS/tasks/feat-login" ] \
      && [ "$(lib ws_wt_path feat-login app)" = "$WS/tasks/feat-login/app" ]; echo $? )"

mkdir -p "$WS/tasks/feat-login/app/src"
inferred=$( cd "$WS/tasks/feat-login/app/src" && lib ws_infer_repo )
check "ws_infer_repo reads the repo from a task worktree path" \
  "$( [ "$inferred" = app ]; echo $? )" "inferred=$inferred"
rm -rf "$WS/tasks/feat-login"

check "without workspace.conf the default branch is an env branch" \
  "$( lib ws_is_env_branch main "$APP"; echo $? )"

check "without workspace.conf other branches are not env branches" \
  "$( ! lib ws_is_env_branch dev "$APP"; echo $? )"

printf 'ENV_BRANCHES="main dev"\n' > "$WS/workspace.conf"
check "ENV_BRANCHES in workspace.conf adds env branches" \
  "$( lib ws_is_env_branch dev "$APP" && ! lib ws_is_env_branch feat/x "$APP"; echo $? )"
rm -f "$WS/workspace.conf"

# ------------------------------------------------------------------------------
# sync-repos
# ------------------------------------------------------------------------------

( cd "$TEST_ROOT/seed-app" && git commit -q --allow-empty -m upstream && git push -q origin main )
want=$(git -C "$TEST_ROOT/seed-app" rev-parse HEAD)
wt sync-repos >/dev/null 2>&1
rc=$?
got=$(git -C "$APP" rev-parse refs/remotes/origin/main)
check "sync-repos fetches new commits into origin/*" \
  "$( [ "$rc" = 0 ] && [ "$want" = "$got" ]; echo $? )" "rc=$rc want=$want got=$got"

git -C "$TEST_ROOT/seed-app" push -q origin --delete feat/extra
wt sync-repos >/dev/null 2>&1
check "sync-repos prunes deleted remote branches" \
  "$( ! git -C "$APP" rev-parse --verify --quiet refs/remotes/origin/feat/extra >/dev/null; echo $? )"

# ------------------------------------------------------------------------------
# Lint
# ------------------------------------------------------------------------------

syntax_bad=
for f in "$REPO_ROOT"/template/scripts/* "$REPO_ROOT"/template/scripts/lib/*.sh; do
  [ -f "$f" ] || continue
  case $f in *.md) continue ;; esac
  bash -n "$f" 2>/dev/null || syntax_bad="$syntax_bad $f"
done
check "every script parses" "$( [ -z "$syntax_bad" ]; echo $? )" "bad:$syntax_bad"

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x -P SCRIPTDIR "$REPO_ROOT"/template/scripts/* "$REPO_ROOT"/template/scripts/lib/*.sh >/dev/null 2>&1; then
    check "shellcheck is clean" 0
  else
    check "shellcheck is clean" 1 "run: shellcheck -x -P SCRIPTDIR template/scripts/* template/scripts/lib/*.sh"
  fi
fi

# ------------------------------------------------------------------------------

printf '\n1..%d\n' "$n"
if [ "$KEEP" = 1 ]; then
  printf 'kept: %s\n' "$TEST_ROOT"
fi
if [ "$failures" -gt 0 ]; then
  printf '%d of %d checks failed\n' "$failures" "$n" >&2
  exit 1
fi
printf 'all %d checks passed\n' "$n"
