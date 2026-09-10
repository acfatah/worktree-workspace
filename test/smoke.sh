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

WS=$TEST_ROOT/ws
mkdir -p "$WS"
cp -R "$REPO_ROOT/template/." "$WS/"

wt() { ( cd "$WS" && ./scripts/"$@" ); }

# ------------------------------------------------------------------------------
# repo-add
# ------------------------------------------------------------------------------

out=$(wt repo-add --no-skills "file://$TEST_ROOT/origin/app.git" app 2>/dev/null)
rc=$?
check "repo-add clones into repos/app" \
  "$( [ "$rc" = 0 ] && [ -e "$WS/repos/app/.git" ] && [ "$out" = "$WS/repos/app" ]; echo $? )" \
  "rc=$rc out=$out"

check "repo-add creates worktrees/app" "$( [ -d "$WS/worktrees/app" ]; echo $? )"

wt repo-add --no-skills "file://$TEST_ROOT/origin/app.git" app >/dev/null 2>&1
check "repo-add refuses an existing repo with exit 4" "$( [ $? = 4 ]; echo $? )"

wt repo-add --no-skills "file://$TEST_ROOT/origin/legacy.git" legacy >/dev/null 2>&1
check "repo-add handles a master-default repository" \
  "$( [ -e "$WS/repos/legacy/.git" ]; echo $? )"

# A local secret for the copy test.
printf 'SECRET=local\n' > "$WS/repos/app/.env"

# ------------------------------------------------------------------------------
# worktree-create
# ------------------------------------------------------------------------------

out=$(wt worktree-create app feat/login 2>/dev/null)
rc=$?
check "worktree-create prints the path on stdout" \
  "$( [ "$rc" = 0 ] && [ "$out" = "$WS/worktrees/app/feat-login" ]; echo $? )" "rc=$rc out=$out"

check "worktree-create sanitizes the directory name" \
  "$( [ -d "$WS/worktrees/app/feat-login" ]; echo $? )"

branch=$(git -C "$WS/worktrees/app/feat-login" symbolic-ref --short HEAD)
check "worktree-create checks out the branch" "$( [ "$branch" = feat/login ]; echo $? )" "branch=$branch"

check "worktree-create copies ignored .env" \
  "$( [ -f "$WS/worktrees/app/feat-login/.env" ]; echo $? )"

check "worktree-create leaves tracked .env.example to the checkout" \
  "$( [ -f "$WS/worktrees/app/feat-login/.env.example" ]; echo $? )"

check "worktree-create links .scratch" \
  "$( [ -d "$WS/worktrees/app/feat-login/.scratch" ]; echo $? )"

check "worktree-create creates scratch/active/<feature>" \
  "$( [ -d "$WS/scratch/active/login" ]; echo $? )"

up=$(git -C "$WS/repos/app" for-each-ref --format='%(upstream:short)' refs/heads/feat/login)
check "a new branch gets no upstream until it is pushed" "$( [ -z "$up" ]; echo $? )" "upstream=$up"

wt worktree-create app fix/typo >/dev/null 2>&1
count=$(grep -cxF '.scratch' "$WS/repos/app/.git/info/exclude" 2>/dev/null || echo 0)
check "two creates leave exactly one .scratch line in the shared exclude file" \
  "$( [ "$count" = 1 ]; echo $? )" "count=$count"

wt worktree-create app feat/login >/dev/null 2>&1
check "re-creating the same worktree is an idempotent exit 0" "$( [ $? = 0 ]; echo $? )"

wt worktree-create nosuch feat/x >/dev/null 2>&1
check "an unknown repository exits 3" "$( [ $? = 3 ]; echo $? )"

wt worktree-create app 'bad..name' >/dev/null 2>&1
check "an invalid branch name exits 2" "$( [ $? = 2 ]; echo $? )"

# ------------------------------------------------------------------------------
# Hooks
# ------------------------------------------------------------------------------

mkdir -p "$WS/repos/app/.workflow"
cat > "$WS/repos/app/.workflow/post-create" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
env | grep '^WORKFLOW_' | sort > "$WORKFLOW_ROOT/hook-env.txt"
pwd > "$WORKFLOW_ROOT/hook-cwd.txt"
HOOK
chmod +x "$WS/repos/app/.workflow/post-create"

wt worktree-create app feat/hooked >/dev/null 2>&1
check "post-create runs" "$( [ -f "$WS/hook-env.txt" ]; echo $? )"

check "post-create runs inside the worktree" \
  "$( [ "$(cat "$WS/hook-cwd.txt" 2>/dev/null)" = "$WS/worktrees/app/feat-hooked" ]; echo $? )" \
  "cwd=$(cat "$WS/hook-cwd.txt" 2>/dev/null)"

check "post-create receives WORKFLOW_SLUG" \
  "$( grep -qx 'WORKFLOW_SLUG=hooked' "$WS/hook-env.txt"; echo $? )" \
  "$(cat "$WS/hook-env.txt" 2>/dev/null)"

check "post-create receives WORKFLOW_BRANCH" \
  "$( grep -qx 'WORKFLOW_BRANCH=feat/hooked' "$WS/hook-env.txt"; echo $? )"

printf '#!/usr/bin/env bash\nexit 3\n' > "$WS/repos/app/.workflow/post-create"
chmod +x "$WS/repos/app/.workflow/post-create"
wt worktree-create app feat/badhook >/dev/null 2>&1
rc=$?
check "a failing post-create exits 5" "$( [ "$rc" = 5 ]; echo $? )" "rc=$rc"
check "a failing post-create leaves the worktree in place" \
  "$( [ -d "$WS/worktrees/app/feat-badhook" ]; echo $? )"

printf '#!/usr/bin/env bash\nexit 0\n' > "$WS/repos/app/.workflow/post-create"
chmod -x "$WS/repos/app/.workflow/post-create"
wt worktree-create app feat/nonexec >/dev/null 2>&1
check "a non-executable hook warns but succeeds" "$( [ $? = 0 ]; echo $? )"
rm -rf "$WS/repos/app/.workflow"

# ------------------------------------------------------------------------------
# worktree-list
# ------------------------------------------------------------------------------

printf 'dirt\n' > "$WS/worktrees/app/fix-typo/scratchfile"
rows=$(wt worktree-list --porcelain 2>/dev/null)
rc=$?
check "worktree-list --porcelain exits 0 without gh" "$( [ "$rc" = 0 ]; echo $? )"

fields=$(printf '%s\n' "$rows" | head -n 1 | awk -F'\t' '{print NF}')
check "worktree-list --porcelain emits 10 fields" "$( [ "$fields" = 10 ]; echo $? )" "fields=$fields"

dirty=$(printf '%s\n' "$rows" | awk -F'\t' '$2 == "fix/typo" { print $5 }')
check "worktree-list reports a dirty worktree" "$( [ "$dirty" = 1 ]; echo $? )" "dirty=$dirty"

pr=$(printf '%s\n' "$rows" | head -n 1 | cut -f10)
check "the pull request column degrades to '-' without gh" "$( [ "$pr" = '-' ]; echo $? )" "pr=$pr"

# ------------------------------------------------------------------------------
# worktree-retire
# ------------------------------------------------------------------------------

wt worktree-retire app fix/typo >/dev/null 2>&1
rc=$?
check "retiring a dirty worktree exits 4" "$( [ "$rc" = 4 ]; echo $? )" "rc=$rc"
check "a dirty worktree survives a refused retire" \
  "$( [ -d "$WS/worktrees/app/fix-typo" ]; echo $? )"

git -C "$WS/worktrees/app/feat-login" commit -q --allow-empty -m work
wt worktree-retire app feat/login >/dev/null 2>&1
rc=$?
check "retiring with unpushed commits exits 4" "$( [ "$rc" = 4 ]; echo $? )" "rc=$rc"

wt worktree-retire --force app fix/typo >/dev/null 2>&1
check "--force retires a dirty worktree" \
  "$( [ ! -d "$WS/worktrees/app/fix-typo" ]; echo $? )"

git -C "$WS/worktrees/app/feat-login" push -q -u origin feat/login
wt worktree-retire app feat/login >/dev/null 2>&1
rc=$?
check "retiring a pushed worktree succeeds" "$( [ "$rc" = 0 ]; echo $? )" "rc=$rc"
check "retire removes the worktree" "$( [ ! -d "$WS/worktrees/app/feat-login" ]; echo $? )"
check "retire archives the scratch directory" "$( [ -d "$WS/scratch/archive/login" ]; echo $? )"
check "retire empties scratch/active" "$( [ ! -d "$WS/scratch/active/login" ]; echo $? )"

# Same feature again: the archive must not be merged into.
wt worktree-create app feat/login >/dev/null 2>&1
wt worktree-retire --force app feat/login >/dev/null 2>&1
stamped=$(ls -d "$WS"/scratch/archive/login-* 2>/dev/null | head -n 1)
check "a second archive of the same feature is timestamped" \
  "$( [ -n "$stamped" ]; echo $? )" "archive: $(ls "$WS/scratch/archive" | tr '\n' ' ')"

mkdir -p "$WS/repos/app/.workflow"
printf '#!/usr/bin/env bash\nexit 4\n' > "$WS/repos/app/.workflow/pre-retire"
chmod +x "$WS/repos/app/.workflow/pre-retire"
wt worktree-create app feat/keepme >/dev/null 2>&1
wt worktree-retire app feat/keepme >/dev/null 2>&1
rc=$?
check "a failing pre-retire exits 5" "$( [ "$rc" = 5 ]; echo $? )" "rc=$rc"
check "a failing pre-retire leaves the worktree in place" \
  "$( [ -d "$WS/worktrees/app/feat-keepme" ]; echo $? )"
rm -rf "$WS/repos/app/.workflow"
wt worktree-retire --force app feat/keepme >/dev/null 2>&1

# ------------------------------------------------------------------------------
# sync-repos
# ------------------------------------------------------------------------------

( cd "$TEST_ROOT/seed-app" && git commit -q --allow-empty -m upstream && git push -q origin main )
before=$(git -C "$WS/repos/app" rev-parse HEAD)
wt sync-repos >/dev/null 2>&1
rc=$?
after=$(git -C "$WS/repos/app" rev-parse HEAD)
check "sync-repos fast-forwards the main clone" \
  "$( [ "$rc" = 0 ] && [ "$before" != "$after" ]; echo $? )" "rc=$rc"

git -C "$WS/repos/app" commit -q --allow-empty -m divergent
before=$(git -C "$WS/repos/app" rev-parse HEAD)
( cd "$TEST_ROOT/seed-app" && git commit -q --allow-empty -m more && git push -q origin main )
wt sync-repos >/dev/null 2>&1
rc=$?
after=$(git -C "$WS/repos/app" rev-parse HEAD)
check "a divergent main clone fails with exit 7 and is not rewritten" \
  "$( [ "$rc" = 7 ] && [ "$before" = "$after" ]; echo $? )" "rc=$rc"

git -C "$WS/repos/app" reset -q --hard origin/main

printf 'dirt\n' > "$WS/repos/app/untracked"
wt sync-repos >/dev/null 2>&1
check "a dirty main clone is skipped, not failed" "$( [ $? = 0 ]; echo $? )"
rm -f "$WS/repos/app/untracked"

# ------------------------------------------------------------------------------
# worktree-prune
# ------------------------------------------------------------------------------

wt worktree-create app feat/landed >/dev/null 2>&1
git -C "$WS/worktrees/app/feat-landed" commit -q --allow-empty -m landed
git -C "$WS/worktrees/app/feat-landed" push -q -u origin feat/landed
git -C "$WS/worktrees/app/feat-landed" push -q origin HEAD:main
git -C "$WS/repos/app" push -q origin --delete feat/landed

wt worktree-prune >/dev/null 2>&1
rc=$?
check "worktree-prune dry run exits 0" "$( [ "$rc" = 0 ]; echo $? )" "rc=$rc"
check "worktree-prune dry run removes nothing" \
  "$( [ -d "$WS/worktrees/app/feat-landed" ]; echo $? )"

wt worktree-prune --yes >/dev/null 2>&1
check "worktree-prune --yes retires the merged worktree" \
  "$( [ ! -d "$WS/worktrees/app/feat-landed" ]; echo $? )"

wt worktree-create app feat/fresh >/dev/null 2>&1
wt worktree-prune --yes >/dev/null 2>&1
check "worktree-prune keeps a branch with no commits yet" \
  "$( [ -d "$WS/worktrees/app/feat-fresh" ]; echo $? )"

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
  if shellcheck -x "$REPO_ROOT"/template/scripts/* "$REPO_ROOT"/template/scripts/lib/*.sh >/dev/null 2>&1; then
    check "shellcheck is clean" 0
  else
    check "shellcheck is clean" 1 "run: shellcheck -x template/scripts/* template/scripts/lib/*.sh"
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
