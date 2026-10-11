#!/usr/bin/env bash
#
# End-to-end smoke test for template/scripts.
#
# Builds throwaway git repositories under a temporary directory and exercises
# every script against them. No network, no dependencies beyond bash and git.
#
#   bash test/smoke.sh [--keep] [--filter <substring>] [--verbose]
#
# --filter still runs every check, since each builds on the last, but prints
# only those whose description contains the substring. Failures always print.

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
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
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
shown=0
failures=0
skipped=0
current=

t() {
  current=$1
  n=$((n + 1))
}

skip_filtered() {
  case ${1:-} in
    *"$FILTER"*) return 1 ;;
    *) return 0 ;;
  esac
}

pass() {
  skip_filtered "$current" && return 0
  shown=$((shown + 1))
  printf 'ok %d - %s\n' "$shown" "$current"
}

fail() {
  # Failures print even outside --filter, so a filtered run cannot hide one.
  shown=$((shown + 1))
  printf 'not ok %d - %s\n' "$shown" "$current"
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

skip() {
  # skip DESCRIPTION REASON
  t "$1"
  skip_filtered "$current" && return 0
  shown=$((shown + 1))
  printf 'ok %d - %s # SKIP %s\n' "$shown" "$current" "$2"
  skipped=$((skipped + 1))
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

reserved_rc=
for reserved in drafts generated NOTES.md CLAUDE.md .claude ..; do
  wt repo-add "file://$TEST_ROOT/origin/app.git" "$reserved" >/dev/null 2>&1
  rc=$?
  [ "$rc" = 2 ] || reserved_rc="$reserved_rc $reserved=$rc"
done
check "repo-add refuses names reserved for the task folder with exit 2" \
  "$( [ -z "$reserved_rc" ] && [ ! -e "$WS/repos/drafts.git" ]; echo $? )" "got:$reserved_rc"

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
  "$( ! lib ws_is_env_branch feat/x "$APP"; echo $? )"

check "without workspace.conf the built-in list makes dev an env branch" \
  "$( lib ws_is_env_branch dev "$APP" && lib ws_is_env_branch staging "$APP"; echo $? )"

printf 'ENV_BRANCHES="main dev"\n' > "$WS/workspace.conf"
check "ENV_BRANCHES in workspace.conf adds env branches" \
  "$( lib ws_is_env_branch dev "$APP" && ! lib ws_is_env_branch feat/x "$APP" \
      && ! lib ws_is_env_branch staging "$APP"; echo $? )"
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
# task-create / task-add
# ------------------------------------------------------------------------------

LEGACY=$WS/repos/legacy.git

# upstream DIR - the upstream of DIR's checked-out branch, or nothing.
upstream() { git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null; }
branch_of() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null; }

# Fixtures: a pushed feature branch, and branches carrying post-create hooks.
(
  cd "$TEST_ROOT/seed-app"
  git switch -qc feat/remote && git commit -q --allow-empty -m remote && git push -q origin feat/remote
  git switch -qc feat/hooked main
  mkdir -p .workflow
  cat > .workflow/post-create <<'HOOK'
#!/bin/sh
printf '%s\n' "$WORKFLOW_KIND" "$WORKFLOW_TASK" "$WORKFLOW_TASK_DIR" "$WORKFLOW_REPO_DIR" "$PWD" > "$WORKFLOW_TASK_DIR/hook.out"
HOOK
  chmod +x .workflow/post-create
  git add -A && git commit -qm hook && git push -q origin feat/hooked
  git switch -qc feat/badhook main
  mkdir -p .workflow
  printf '#!/bin/sh\nexit 1\n' > .workflow/post-create
  chmod +x .workflow/post-create
  git add -A && git commit -qm badhook && git push -q origin feat/badhook
  git switch -q main
)

out=$(wt task-create feat/login app 2>/dev/null)
rc=$?
T=$WS/tasks/feat-login
check "task-create makes tasks/<task> and prints it" \
  "$( [ "$rc" = 0 ] && [ "$out" = "$T" ]; echo $? )" "rc=$rc out=$out"

check "task-create checks out the branch in tasks/<task>/<repo>" \
  "$( [ "$(branch_of "$T/app")" = feat/login ]; echo $? )" "branch=$(branch_of "$T/app")"

check "a new task branch has no upstream" "$( [ -z "$(upstream "$T/app")" ]; echo $? )" \
  "upstream=$(upstream "$T/app")"

check "task-create writes CLAUDE.md, NOTES.md and .claude/plans/" \
  "$( [ -f "$T/CLAUDE.md" ] && [ -f "$T/NOTES.md" ] && [ -d "$T/.claude/plans" ] \
      && grep -q 'feat/login' "$T/CLAUDE.md" && grep -q 'drafts/' "$T/CLAUDE.md" \
      && grep -q 'generated/' "$T/CLAUDE.md"; echo $? )"

printf 'my notes\n' >> "$T/NOTES.md"
cp "$T/CLAUDE.md" "$TEST_ROOT/claude.before"
wt task-create feat/login app >/dev/null 2>&1
rc=$?
check "re-running task-create succeeds and keeps the task files" \
  "$( [ "$rc" = 0 ] && cmp -s "$T/CLAUDE.md" "$TEST_ROOT/claude.before" \
      && grep -q 'my notes' "$T/NOTES.md"; echo $? )" "rc=$rc"

wt task-create feat/multi app legacy >/dev/null 2>&1
M=$WS/tasks/feat-multi
check "task-create bases each repo on its own default branch" \
  "$( [ "$(git -C "$M/app" rev-parse HEAD)" = "$(git -C "$APP" rev-parse origin/main)" ] \
      && [ "$(git -C "$M/legacy" rev-parse HEAD)" = "$(git -C "$LEGACY" rev-parse origin/master)" ]; echo $? )"

wt task-create feat/x app nosuch >/dev/null 2>&1
rc=$?
check "task-create refuses an unknown repo with exit 3, creating nothing" \
  "$( [ "$rc" = 3 ] && [ ! -e "$WS/tasks/feat-x" ]; echo $? )" "rc=$rc"

wt task-create feat/remote app >/dev/null 2>&1
check "task-create tracks an existing remote branch" \
  "$( [ "$(upstream "$WS/tasks/feat-remote/app")" = origin/feat/remote ]; echo $? )" \
  "upstream=$(upstream "$WS/tasks/feat-remote/app")"

wt task-create --base feat/remote feat/based app >/dev/null 2>&1
check "task-create --base starts a new branch at that ref" \
  "$( [ "$(git -C "$WS/tasks/feat-based/app" rev-parse HEAD)" = "$(git -C "$APP" rev-parse origin/feat/remote)" ]; echo $? )"

out=$(wt task-add feat-login legacy 2>/dev/null)
rc=$?
check "task-add adds a repo on the task's branch" \
  "$( [ "$rc" = 0 ] && [ "$out" = "$T" ] && [ "$(branch_of "$T/legacy")" = feat/login ]; echo $? )" \
  "rc=$rc out=$out branch=$(branch_of "$T/legacy")"

wt task-add nosuch app >/dev/null 2>&1
check "task-add refuses an unknown task with exit 3" "$( [ $? = 3 ]; echo $? )"

wt task-create main app >/dev/null 2>"$TEST_ROOT/envtask.err"
rc=$?
check "task-create refuses an env branch with exit 4 and points to branch-add" \
  "$( [ "$rc" = 4 ] && [ ! -e "$WS/tasks/main" ] \
      && grep -q 'scripts/branch-add main app' "$TEST_ROOT/envtask.err"; echo $? )" \
  "rc=$rc" "$(cat "$TEST_ROOT/envtask.err")"

printf 'ENV_BRANCHES="staging"\n' > "$WS/workspace.conf"
wt task-create staging app >/dev/null 2>&1
rc=$?
check "task-create refuses a branch listed in ENV_BRANCHES with exit 4" \
  "$( [ "$rc" = 4 ] && [ ! -e "$WS/tasks/staging" ]; echo $? )" "rc=$rc"
rm -f "$WS/workspace.conf"

mkdir -p "$WS/shared/app/config"
printf 'SECRET=1\n' > "$WS/shared/app/.env"
printf 'local: true\n' > "$WS/shared/app/config/local.yml"
printf 'shadow\n' > "$WS/shared/app/README.md"
wt task-create feat/shared app >/dev/null 2>"$TEST_ROOT/shared.err"
S=$WS/tasks/feat-shared/app
check "task-create copies shared/<repo>/ into the worktree" \
  "$( [ "$(cat "$S/.env" 2>/dev/null)" = SECRET=1 ] && [ -f "$S/config/local.yml" ]; echo $? )"
check "task-create never overwrites a file with a shared copy" \
  "$( [ "$(cat "$S/README.md")" = app ]; echo $? )"
check "task-create warns about a shared file the repo does not ignore" \
  "$( grep -q 'config/local.yml is not ignored' "$TEST_ROOT/shared.err" \
      && ! grep -q '\.env is not ignored' "$TEST_ROOT/shared.err"; echo $? )" "$(cat "$TEST_ROOT/shared.err")"
wt task-create --no-shared feat/noshared app >/dev/null 2>&1
check "task-create --no-shared skips the copy" \
  "$( [ ! -e "$WS/tasks/feat-noshared/app/.env" ]; echo $? )"
rm -rf "$WS/shared/app"

wt task-create feat/hooked app >/dev/null 2>&1
H=$WS/tasks/feat-hooked
want=$(printf '%s\n' task feat-hooked "$H" "$APP" "$H/app")
got=$(cat "$H/hook.out" 2>/dev/null)
check "post-create runs in the worktree with the task environment" \
  "$( [ "$got" = "$want" ]; echo $? )" "want=$want" "got=$got"

rm -f "$H/hook.out"
wt task-add --no-hooks feat-hooked legacy >/dev/null 2>&1
check "--no-hooks skips post-create" "$( [ ! -e "$H/hook.out" ]; echo $? )"

wt task-create feat/badhook app >/dev/null 2>&1
rc=$?
check "a failing post-create exits 5 and keeps the worktree" \
  "$( [ "$rc" = 5 ] && [ -e "$WS/tasks/feat-badhook/app/.git" ]; echo $? )" "rc=$rc"

wt task-create feat/a-b app >/dev/null 2>&1
wt task-create feat-a/b app >/dev/null 2>&1
check "two branches with one task folder exit 4" "$( [ $? = 4 ]; echo $? )"

mkdir -p "$WS/tasks/feat-occ/app"
touch "$WS/tasks/feat-occ/app/stray"
wt task-create feat/occ app >/dev/null 2>&1
check "a non-empty unregistered target exits 4" "$( [ $? = 4 ]; echo $? )"
rm -f "$WS/tasks/feat-occ/app/stray"
wt task-create feat/occ app >/dev/null 2>&1
check "an empty target directory is reused" "$( [ $? = 0 ]; echo $? )"

# ------------------------------------------------------------------------------
# branch-add / branch-list / branch-remove
# ------------------------------------------------------------------------------

( cd "$TEST_ROOT/seed-app" && git push -q origin main:dev feat/hooked:feat/review )
( cd "$TEST_ROOT/seed-legacy" && git push -q origin master:dev )
git -C "$APP" fetch -q origin

# sync-repos above moved origin/main past the local main that repo-add made.
out=$(wt branch-add main app 2>/dev/null)
rc=$?
B=$WS/branches/main
check "branch-add checks out branches/<name>/<repo> and prints the folder" \
  "$( [ "$rc" = 0 ] && [ "$out" = "$B" ] && [ "$(branch_of "$B/app")" = main ] \
      && [ "$(upstream "$B/app")" = origin/main ]; echo $? )" \
  "rc=$rc out=$out branch=$(branch_of "$B/app") upstream=$(upstream "$B/app")"

check "branch-add fast-forwards a stale local branch" \
  "$( [ "$(git -C "$B/app" rev-parse HEAD)" = "$(git -C "$APP" rev-parse origin/main)" ]; echo $? )"

wt branch-add nosuch app >/dev/null 2>&1
rc=$?
check "branch-add refuses a branch missing locally and on origin with exit 3" \
  "$( [ "$rc" = 3 ] && [ ! -e "$WS/branches/nosuch" ]; echo $? )" "rc=$rc"

wt branch-add main legacy >/dev/null 2>&1
rc=$?
check "branch-add checks every repository before creating anything" \
  "$( [ "$rc" = 3 ] && [ ! -e "$B/legacy" ]; echo $? )" "rc=$rc"

wt branch-add feat/login app >/dev/null 2>&1
check "branch-add refuses a branch a task has checked out with exit 4" "$( [ $? = 4 ]; echo $? )"

wt branch-add dev app >/dev/null 2>&1
wt branch-add dev legacy >/dev/null 2>&1
rc=$?
D=$WS/branches/dev
check "re-running branch-add adds a repository on the same branch" \
  "$( [ "$rc" = 0 ] && [ "$(upstream "$D/app")" = origin/dev ] \
      && [ "$(upstream "$D/legacy")" = origin/dev ]; echo $? )" \
  "rc=$rc app=$(upstream "$D/app") legacy=$(upstream "$D/legacy")"

mkdir -p "$WS/shared/app"
printf 'SECRET=1\n' > "$WS/shared/app/.env"
wt branch-add feat/review app >/dev/null 2>&1
V=$WS/branches/feat-review
want=$(printf '%s\n' branch feat-review "$V" "$APP" "$V/app")
got=$(cat "$V/hook.out" 2>/dev/null)
check "branch-add copies shared/ and runs post-create with WORKFLOW_KIND=branch" \
  "$( [ "$(cat "$V/app/.env" 2>/dev/null)" = SECRET=1 ] && [ "$got" = "$want" ]; echo $? )" \
  "want=$want" "got=$got"
rm -rf "$WS/shared/app"

touch "$B/app/stray"
porc=$(wt branch-list --porcelain main 2>/dev/null)
check "branch-list --porcelain prints the row and its state" \
  "$( [ "$(printf '%s\n' "$porc" | cut -f1,2,3,5 | tr '\t' ' ')" = 'main app main dirty' ]; echo $? )" \
  "$porc"
rm -f "$B/app/stray"

out=$(wt branch-list 2>/dev/null)
check "branch-list lists every checkout" \
  "$( printf '%s\n' "$out" | grep -q '^dev ' && printf '%s\n' "$out" | grep -q '^feat-review '; echo $? )" "$out"

touch "$D/app/stray"
wt branch-remove dev >/dev/null 2>&1
rc=$?
check "branch-remove refuses a dirty worktree with exit 4" \
  "$( [ "$rc" = 4 ] && [ -e "$D/app/.git" ]; echo $? )" "rc=$rc"
rm -f "$D/app/stray"

git -C "$D/legacy" commit -q --allow-empty -m local
wt branch-remove dev >/dev/null 2>&1
rc=$?
check "branch-remove refuses unpushed commits with exit 4" \
  "$( [ "$rc" = 4 ] && [ -e "$D/legacy/.git" ]; echo $? )" "rc=$rc"
git -C "$D/legacy" reset -q --hard HEAD~1

wt branch-remove dev >/dev/null 2>&1
rc=$?
check "branch-remove removes the folder and keeps an env branch" \
  "$( [ "$rc" = 0 ] && [ ! -e "$D" ] && [ -d "$B" ] \
      && git -C "$APP" show-ref --verify --quiet refs/heads/dev \
      && git -C "$LEGACY" show-ref --verify --quiet refs/heads/dev; echo $? )" "rc=$rc"

( cd "$V/app" && "$WS/scripts/branch-remove" >/dev/null 2>&1 )
rc=$?
check "branch-remove with no argument removes the checkout holding the cwd" \
  "$( [ ! -e "$V/app" ] && ! git -C "$APP" show-ref --verify --quiet refs/heads/feat/review; echo $? )" \
  "rc=$rc"
check "branch-remove keeps a folder with leftover files and exits 7" \
  "$( [ "$rc" = 7 ] && [ -f "$V/hook.out" ]; echo $? )" "rc=$rc"
rm -f "$V/hook.out"
rmdir "$V"

wt branch-remove nosuch >/dev/null 2>&1
check "branch-remove refuses an unknown checkout with exit 3" "$( [ $? = 3 ]; echo $? )"

# ------------------------------------------------------------------------------
# ws_landed / task-list
# ------------------------------------------------------------------------------

# landed REPO_DIR BRANCH - just the verdict.
landed() { lib ws_landed "$1" "$2" | cut -f1; }

# row TASK REPO FIELD - one --porcelain field (1-based) for TASK/REPO.
row() { wt task-list --porcelain "$1" 2>/dev/null | awk -F'\t' -v r="$2" -v f="$3" '$2 == r { print $f }'; }

wt task-create feat/land app legacy >/dev/null 2>&1
L=$WS/tasks/feat-land
check "ws_landed says new for a branch with no commits" \
  "$( [ "$(landed "$APP" feat/land)" = new ]; echo $? )" "verdict=$(landed "$APP" feat/land)"

( cd "$L/app" && git commit -q --allow-empty -m land-app && git push -q -u origin feat/land )
( cd "$L/legacy" && git commit -q --allow-empty -m land-legacy && git push -q -u origin feat/land )
check "ws_landed says open for a pushed, unmerged branch" \
  "$( [ "$(landed "$APP" feat/land)" = open ]; echo $? )" "verdict=$(landed "$APP" feat/land)"

( cd "$TEST_ROOT/seed-app" && git fetch -q origin feat/land && git merge -q --ff-only FETCH_HEAD \
    && git push -q origin main )
git -C "$APP" fetch -q origin
check "ws_landed says merged once the branch is in origin/<default>" \
  "$( [ "$(landed "$APP" feat/land)" = merged ]; echo $? )" "verdict=$(landed "$APP" feat/land)"

check "ws_landed still says new for a fresh branch once the base moves on" \
  "$( [ "$(landed "$APP" feat/login)" = new ]; echo $? )" "verdict=$(landed "$APP" feat/login)"

wt task-create feat/gone app >/dev/null 2>&1
( cd "$WS/tasks/feat-gone/app" && git commit -q --allow-empty -m gone && git push -q -u origin feat/gone )
git -C "$TEST_ROOT/seed-app" push -q origin --delete feat/gone
git -C "$APP" fetch -q --prune origin
check "ws_landed says gone once the remote branch is deleted" \
  "$( [ "$(landed "$APP" feat/gone)" = gone ]; echo $? )" "verdict=$(landed "$APP" feat/gone)"

porc=$(wt task-list --porcelain feat-land 2>/dev/null)
check "task-list --porcelain prints one row per repo of a task" \
  "$( [ "$(printf '%s\n' "$porc" | wc -l | tr -d ' ')" = 2 ] \
      && [ "$(printf '%s\n' "$porc" | cut -f1,2,3 | tr '\t\n' ' ')" = 'feat-land app feat/land feat-land legacy feat/land ' ]; echo $? )" \
  "$porc"

check "task-list --porcelain reports each repo's landing" \
  "$( [ "$(row feat-land app 11)" = merged ] && [ "$(row feat-land legacy 11)" = open ]; echo $? )" \
  "app=$(row feat-land app 11) legacy=$(row feat-land legacy 11)"

out=$(wt task-list feat-land 2>/dev/null)
check "task-list shows a partial landing" \
  "$( printf '%s\n' "$out" | head -n 1 | grep -q 'landed 1/2'; echo $? )" "$out"

touch "$L/app/stray"
check "task-list shows a dirty worktree" \
  "$( [ "$(row feat-land app 5)" = dirty ]; echo $? )" "state=$(row feat-land app 5)"
rm -f "$L/app/stray"

out=$(wt task-list 2>/dev/null)
check "task-list lists every task" \
  "$( printf '%s\n' "$out" | grep -q '^feat-land ' && printf '%s\n' "$out" | grep -q '^feat-login '; echo $? )" "$out"

wt task-list nosuch >/dev/null 2>&1
check "task-list refuses an unknown task with exit 3" "$( [ $? = 3 ]; echo $? )"

# ------------------------------------------------------------------------------
# task-retire
# ------------------------------------------------------------------------------

touch "$L/app/stray"
wt task-retire feat-land >/dev/null 2>&1
rc=$?
check "task-retire refuses a dirty worktree with exit 4, changing nothing" \
  "$( [ "$rc" = 4 ] && [ -e "$L/app/.git" ] && [ -e "$L/legacy/.git" ] \
      && git -C "$APP" show-ref --verify --quiet refs/heads/feat/land; echo $? )" "rc=$rc"
rm -f "$L/app/stray"

git -C "$L/legacy" commit -q --allow-empty -m unpushed
wt task-retire feat-land >/dev/null 2>&1
rc=$?
check "task-retire refuses unpushed commits with exit 4" \
  "$( [ "$rc" = 4 ] && [ -e "$L/legacy/.git" ]; echo $? )" "rc=$rc"
git -C "$L/legacy" reset -q --hard HEAD~1

# Plan links: one at task level, one dangling, one inside a worktree (ignored
# there through the bare repository's shared info/exclude).
mkdir -p "$HOME/.claude/plans" "$L/app/.claude/plans"
printf 'task plan\n' > "$HOME/.claude/plans/task.md"
printf 'worktree plan\n' > "$HOME/.claude/plans/wt.md"
ln -s "$HOME/.claude/plans/task.md" "$L/.claude/plans/task.md"
ln -s "$HOME/.claude/plans/nope.md" "$L/.claude/plans/dangling.md"
ln -s "$HOME/.claude/plans/wt.md" "$L/app/.claude/plans/wt.md"
printf '.claude/plans/\n' >> "$APP/info/exclude"

out=$(wt task-retire feat-land 2>"$TEST_ROOT/retire.err")
rc=$?
A=$WS/archive/feat-land
check "task-retire archives the task and prints the archive path" \
  "$( [ "$rc" = 0 ] && [ "$out" = "$A" ] && [ ! -e "$L" ] && [ -f "$A/NOTES.md" ]; echo $? )" \
  "rc=$rc out=$out" "$(cat "$TEST_ROOT/retire.err")"

check "task-retire removes every worktree" \
  "$( [ -z "$(lib ws_task_worktrees feat-land)" ]; echo $? )" "$(lib ws_task_worktrees feat-land)"

check "task-retire deletes the task's local branches and keeps the default" \
  "$( ! git -C "$APP" show-ref --verify --quiet refs/heads/feat/land \
      && ! git -C "$LEGACY" show-ref --verify --quiet refs/heads/feat/land \
      && git -C "$APP" show-ref --verify --quiet refs/heads/main; echo $? )"

check "task-retire replaces a plan link with a real copy" \
  "$( [ ! -L "$A/.claude/plans/task.md" ] && [ "$(cat "$A/.claude/plans/task.md")" = 'task plan' ]; echo $? )"

check "task-retire keeps a dangling plan link" "$( [ -L "$A/.claude/plans/dangling.md" ]; echo $? )"

check "task-retire rescues a worktree's own plans as real copies" \
  "$( [ ! -L "$A/.claude/plans/app/wt.md" ] \
      && [ "$(cat "$A/.claude/plans/app/wt.md" 2>/dev/null)" = 'worktree plan' ]; echo $? )"

wt task-create feat/land app >/dev/null 2>&1
out=$(wt task-retire feat-land 2>/dev/null)
rc=$?
check "a second retire of the same name appends the date" \
  "$( [ "$rc" = 0 ] && [ "$out" = "$A-$(date +%Y-%m-%d)" ] && [ -d "$out" ]; echo $? )" "rc=$rc out=$out"

(
  cd "$TEST_ROOT/seed-app"
  git switch -qc feat/retirehook main
  mkdir -p .workflow
  cat > .workflow/pre-retire <<HOOK
#!/bin/sh
printf '%s\n' "\$WORKFLOW_EVENT" "\$WORKFLOW_TASK" "\$PWD" > "$TEST_ROOT/retire-hook.out"
if [ -e "$TEST_ROOT/hookfail" ]; then exit 1; fi
HOOK
  chmod +x .workflow/pre-retire
  git add -A && git commit -qm retirehook && git push -q origin feat/retirehook
  git switch -q main
)
wt task-create feat/retirehook app >/dev/null 2>&1
R=$WS/tasks/feat-retirehook
touch "$TEST_ROOT/hookfail"
wt task-retire feat-retirehook >/dev/null 2>&1
rc=$?
check "a failing pre-retire exits 5 and removes nothing" \
  "$( [ "$rc" = 5 ] && [ -e "$R/app/.git" ]; echo $? )" "rc=$rc"

want=$(printf '%s\n' pre-retire feat-retirehook "$R/app")
got=$(cat "$TEST_ROOT/retire-hook.out" 2>/dev/null)
check "pre-retire runs in the worktree with the task environment" \
  "$( [ "$got" = "$want" ]; echo $? )" "want=$want" "got=$got"

rm -f "$TEST_ROOT/retire-hook.out"
wt task-retire --no-hooks feat-retirehook >/dev/null 2>&1
rc=$?
check "task-retire --no-hooks skips pre-retire" \
  "$( [ "$rc" = 0 ] && [ ! -e "$TEST_ROOT/retire-hook.out" ] && [ ! -e "$R" ]; echo $? )" "rc=$rc"
rm -f "$TEST_ROOT/hookfail"

wt task-create feat/infer app >/dev/null 2>&1
( cd "$WS/tasks/feat-infer/app" && "$WS/scripts/task-retire" >/dev/null 2>&1 )
rc=$?
check "task-retire with no argument retires the task holding the cwd" \
  "$( [ "$rc" = 0 ] && [ -d "$WS/archive/feat-infer" ] && [ ! -e "$WS/tasks/feat-infer" ]; echo $? )" "rc=$rc"

wt task-retire nosuch >/dev/null 2>&1
check "task-retire refuses an unknown task with exit 3" "$( [ $? = 3 ]; echo $? )"


# ------------------------------------------------------------------------------
# task-prune
# ------------------------------------------------------------------------------

# push_task TASK REPO... - commit and push the task's branch in each repo.
push_task() {
  local task=$1 r
  shift
  for r in "$@"; do
    ( cd "$WS/tasks/$task/$r" && git commit -q --allow-empty -m "$task $r" \
        && git push -q -u origin "$(git symbolic-ref --short HEAD)" )
  done
}

# merge_on_origin SEED BRANCH TARGET - merge BRANCH into TARGET on origin.
merge_on_origin() {
  ( cd "$TEST_ROOT/$1" && git fetch -q origin "$2" && git merge -q --no-ff --no-edit FETCH_HEAD \
      && git push -q origin "$3" )
}

wt task-create feat/pdone app legacy >/dev/null 2>&1
wt task-create feat/ppart app legacy >/dev/null 2>&1
wt task-create feat/pfresh app >/dev/null 2>&1
wt task-create feat/pdirty app >/dev/null 2>&1
push_task feat-pdone app legacy
push_task feat-ppart app legacy
push_task feat-pdirty app
merge_on_origin seed-app feat/pdone main
merge_on_origin seed-legacy feat/pdone master
merge_on_origin seed-app feat/ppart main
merge_on_origin seed-app feat/pdirty main
touch "$WS/tasks/feat-pdirty/app/stray"
# task-create refuses env branches, so a leftover env task is made by hand.
git -C "$APP" worktree add -q "$WS/tasks/dev/app" dev

PRUNE_SET="feat-pdone feat-ppart feat-pfresh feat-pdirty feat-gone dev"
# shellcheck disable=SC2086
out=$(wt task-prune $PRUNE_SET 2>&1)
rc=$?
verdict() { printf '%s\n' "$out" | awk -v t="$1" '$1 == t { print $2; exit }'; }

check "task-prune lists a fully landed task as retire" \
  "$( [ "$rc" = 0 ] && [ "$(verdict feat-pdone)" = retire ]; echo $? )" "rc=$rc" "$out"
check "task-prune dry run changes nothing" "$( [ -e "$WS/tasks/feat-pdone/app/.git" ]; echo $? )"
check "task-prune keeps a partial landing" "$( [ "$(verdict feat-ppart)" = partial ]; echo $? )" "$out"
check "task-prune keeps a fresh task" "$( [ "$(verdict feat-pfresh)" = keep ]; echo $? )" "$out"
check "task-prune skips a task on an env branch, dev included without workspace.conf" \
  "$( [ "$(verdict dev)" = env ]; echo $? )" "$out"
check "task-prune skips a landed task with a dirty worktree" \
  "$( [ "$(verdict feat-pdirty)" = skip ]; echo $? )" "$out"
check "task-prune sends landed work with unpushed commits to review" \
  "$( [ "$(verdict feat-gone)" = review ]; echo $? )" "$out"

# shellcheck disable=SC2086
out=$(wt task-prune --yes $PRUNE_SET 2>/dev/null)
rc=$?
kept=0
for t in feat-ppart feat-pfresh feat-pdirty feat-gone dev; do
  [ -d "$WS/tasks/$t" ] || kept=1
done
check "task-prune --yes retires only the landed task" \
  "$( [ "$rc" = 0 ] && [ "$out" = "$WS/archive/feat-pdone" ] && [ ! -e "$WS/tasks/feat-pdone" ] \
      && [ "$kept" = 0 ]; echo $? )" "rc=$rc out=$out kept=$kept"
rm -f "$WS/tasks/feat-pdirty/app/stray"

wt task-prune nosuch >/dev/null 2>&1
check "task-prune refuses an unknown task with exit 3" "$( [ $? = 3 ]; echo $? )"

# ------------------------------------------------------------------------------
# sync-repos: branch-checkout fast-forward
# ------------------------------------------------------------------------------

# push_main - a new commit on origin main; prints its id.
push_main() {
  ( cd "$TEST_ROOT/seed-app" && git commit -q --allow-empty -m "${1:-upstream}" \
      && git push -q origin main && git rev-parse HEAD )
}

E=$WS/branches/main/app
FR=$WS/tasks/feat-remote/app
fr_before=$(git -C "$FR" rev-parse HEAD)
( cd "$TEST_ROOT/seed-app" && git switch -q feat/remote && git commit -q --allow-empty -m more \
    && git push -q origin feat/remote && git switch -q main )

want=$(push_main)
wt sync-repos >/dev/null 2>&1
rc=$?
check "sync-repos fast-forwards a clean branch checkout" \
  "$( [ "$rc" = 0 ] && [ "$(git -C "$E" rev-parse HEAD)" = "$want" ]; echo $? )" \
  "rc=$rc want=$want got=$(git -C "$E" rev-parse HEAD)"
check "sync-repos leaves a feature task alone" \
  "$( [ "$(git -C "$FR" rev-parse HEAD)" = "$fr_before" ]; echo $? )"

before=$(git -C "$E" rev-parse HEAD)
push_main >/dev/null
wt sync-repos --no-ff >/dev/null 2>&1
check "sync-repos --no-ff fetches but does not fast-forward" \
  "$( [ "$(git -C "$E" rev-parse HEAD)" = "$before" ] \
      && [ "$(git -C "$APP" rev-parse origin/main)" != "$before" ]; echo $? )"

touch "$E/stray"
wt sync-repos >/dev/null 2>"$TEST_ROOT/sync.err"
rc=$?
check "sync-repos skips a dirty branch checkout and still exits 0" \
  "$( [ "$rc" = 0 ] && [ "$(git -C "$E" rev-parse HEAD)" = "$before" ] \
      && grep -q 'uncommitted changes' "$TEST_ROOT/sync.err"; echo $? )" "rc=$rc" "$(cat "$TEST_ROOT/sync.err")"
rm -f "$E/stray"

git -C "$E" commit -q --allow-empty -m local
before=$(git -C "$E" rev-parse HEAD)
push_main >/dev/null
wt sync-repos >/dev/null 2>"$TEST_ROOT/sync.err"
rc=$?
check "sync-repos skips a diverged branch checkout with a warning" \
  "$( [ "$rc" = 0 ] && [ "$(git -C "$E" rev-parse HEAD)" = "$before" ] \
      && grep -q 'diverged' "$TEST_ROOT/sync.err"; echo $? )" "rc=$rc" "$(cat "$TEST_ROOT/sync.err")"
git -C "$E" reset -q --hard origin/main

# ------------------------------------------------------------------------------
# Lint
# ------------------------------------------------------------------------------

syntax_bad=
scripts=()
for f in "$REPO_ROOT"/template/scripts/* "$REPO_ROOT"/template/scripts/lib/*.sh; do
  [ -f "$f" ] || continue
  case $f in *.md) continue ;; esac
  scripts+=("$f")
  bash -n "$f" 2>/dev/null || syntax_bad="$syntax_bad $f"
done
check "every script parses" "$( [ -z "$syntax_bad" ]; echo $? )" "bad:$syntax_bad"

if ! command -v shellcheck >/dev/null 2>&1; then
  skip "shellcheck is clean" "shellcheck not installed"
elif shellcheck -x -P SCRIPTDIR "${scripts[@]}" >/dev/null 2>&1; then
  check "shellcheck is clean" 0
else
  check "shellcheck is clean" 1 "run: find template/scripts -type f -exec shellcheck -x -P SCRIPTDIR {} +"
fi

# ------------------------------------------------------------------------------

printf '\n1..%d\n' "$shown"
if [ "$KEEP" = 1 ]; then
  printf 'kept: %s\n' "$TEST_ROOT"
fi
if [ "$failures" -gt 0 ]; then
  printf '%d of %d checks failed\n' "$failures" "$shown" >&2
  exit 1
fi
if [ -n "$FILTER" ] && [ "$shown" = 0 ]; then
  printf "no checks match --filter '%s'\n" "$FILTER" >&2
  exit 1
fi
if [ -n "$FILTER" ]; then
  summary="all $shown matching checks passed ($((n - shown)) hidden by --filter)"
else
  summary="all $shown checks passed"
fi
if [ "$skipped" -gt 0 ]; then
  summary="$summary ($skipped skipped)"
fi
printf '%s\n' "$summary"
