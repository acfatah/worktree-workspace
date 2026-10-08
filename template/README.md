# Workspace

One bare clone per repository, and one folder per task holding a worktree of
every repository the task touches, all on the same branch. Notes and plans
live in the task folder, above its worktrees, so they survive the worktrees.
See `CLAUDE.md` for where each kind of document belongs.

```
workspace/                  # a plain folder, not a git repository
├── CLAUDE.md               # placement rules for the task workflow
├── .claude/plans/          # cross-task plan links
├── archive/<task>/         # notes and plans of retired tasks
├── docs/                   # cross-task notes, specs, diagrams
├── repos/<repo>.git/       # bare clone of each repository
├── scripts/                # the seven commands below
├── shared/<repo>/          # ignored local files (.env) for new worktrees
├── tasks/
│   ├── main/               # optional env task: production
│   ├── dev/                # optional env task: development server
│   └── feat-login/         # a task, on branch feat/login
│       ├── CLAUDE.md       # generated: the branch, where notes go
│       ├── NOTES.md        # generated stub
│       ├── .claude/plans/  # this task's plan links
│       ├── app/            # worktree of repos/app.git
│       └── api/            # worktree of repos/api.git
└── workspace.conf          # optional; created when you need it
```

## Requirements

bash 3.2 or newer, git 2.23 or newer. `gh` is optional: without it the pull
request column and merged-PR detection degrade quietly.

If your copy of the scripts is not executable, run `chmod +x scripts/*`.

## The seven commands

| command | what it does |
| --- | --- |
| `scripts/repo-add <url>` | bare-clone a repository into `repos/` |
| `scripts/task-create <branch> <repo>...` | start a task: one worktree per repository |
| `scripts/task-add <task> <repo>...` | add repositories to a task |
| `scripts/task-list` | status of every task and its repositories |
| `scripts/task-retire [<task>]` | remove a task's worktrees and archive its notes |
| `scripts/task-prune` | retire every task whose work has landed |
| `scripts/sync-repos` | fetch every repository, fast-forward env tasks |

Every command takes `-h`. Run them from anywhere: they locate the workspace
from their own path, not from your current directory.

## Conventions

**stdout is payload, stderr is logging.** So this works:

```bash
cd "$(scripts/task-create feat/login app api)"
```

**Exit codes** are shared across all seven commands.

| code | meaning |
| --- | --- |
| 0 | success, including an idempotent no-op |
| 1 | unexpected internal error |
| 2 | usage or validation error |
| 3 | not found: repository, task, branch, base |
| 4 | conflicting state: exists, dirty, unpushed, locked, an env task |
| 5 | a lifecycle hook failed |
| 6 | you declined a confirmation |
| 7 | an external tool failed, or some items of a batch did |

**Environment.** `WORKSPACE_ROOT` overrides workspace detection.
`WORKFLOW_YES=1` answers every prompt yes. `WORKFLOW_NO_HOOKS=1` skips
lifecycle hooks. `WORKFLOW_NO_GH=1` forces the no-GitHub path. `NO_COLOR`
and `FORCE_COLOR` work as usual.

**Task names.** A task folder is its branch with every `/` turned into `-`:
`feat/login` lives in `tasks/feat-login/`. The branch is the same in every
repository of the task, so each repository gets its own PR from it.

## repo-add

    scripts/repo-add [options] <url> [<name>]

      --name <n>      repository name; the clone goes to repos/<n>.git
                      (default: derived from <url>)
      --branch <b>    branch new tasks start from (default: the remote
                      default); recorded as git config workflow.baseBranch

Makes a bare clone at `repos/<name>.git` and prints its path. A bare clone
has no `origin/*` refs by default, so `repo-add` sets the usual fetch
refspec and fetches again, then pins the remote default branch with
`git remote set-head origin -a`. Later commands find a base offline.

It keeps only the default branch as a local branch, tracking
`origin/<default>`. Any other local branch was made by a task. It creates
no worktree; start one with `task-create`.

## task-create

    scripts/task-create [options] <branch> <repo>...

      -b, --base <ref>   base for repositories where <branch> is new
                         (default: each repository's base branch)
          --no-fetch     do not fetch before creating
          --no-hooks     skip .workflow/post-create
          --no-shared    do not copy shared/<repo>/ into new worktrees

Creates `tasks/<task>/` with `CLAUDE.md`, `NOTES.md` and `.claude/plans/`,
then one worktree per repository at `tasks/<task>/<repo>`, all on
`<branch>`. It prints the task path.

**Every repository is checked first**: that it exists, that the target path
is free, that the branch is not checked out elsewhere, and that the base
exists. Nothing is created until all of them pass. A later failure, such as
a hook, keeps what exists. Re-running resumes, because worktrees that
already exist for the branch are skipped. Existing task files are never
overwritten.

Per repository, the branch comes from, in order:

1. **An existing local branch.** When it is behind `origin/<branch>`, it is
   fast-forwarded first.
2. **`origin/<branch>`.** The new local branch tracks it.
3. **A new branch** from `origin/<base>`, where `<base>` is `--base`, else
   the repository's base branch.

A new branch gets **no upstream** until you `git push -u origin <branch>`.
That is deliberate: inheriting the base as upstream breaks `git push`
defaults and makes an untouched branch look merged.

Each new worktree then gets the files from `shared/<repo>/`, and its
`post-create` hook runs.

An env branch, such as `main`, must already exist locally or on origin;
`task-create` never creates one. See [Env tasks](#env-tasks-optional).

## task-add

    scripts/task-add [options] <task> <repo>...

      -b, --base <ref>   base for repositories where the branch is new
          --no-fetch     do not fetch before creating
          --no-hooks     skip .workflow/post-create
          --no-shared    do not copy shared/<repo>/ into new worktrees

Adds worktrees to `tasks/<task>/` on the branch its worktrees already use.
`<task>` is the folder name, such as `feat-login`, or a path to it. The
branch is read from the task's worktrees, so the task needs at least one.
Everything else is `task-create`.

## task-list

    scripts/task-list [--pr|--no-pr] [--fetch] [--porcelain] [<task>...]

Lists every task, then one row per repository: state (`clean`, `dirty`,
`locked`, `missing`), ahead and behind counts, upstream, pull request, and
whether the branch has landed. The task line shows `landed` when every
repository has, `landed 1/2` when only some have, and `env` for an env task.

It touches the network only with `--fetch` or when the pull request column
is on, which is the default when `gh` is usable.

`--porcelain` prints tab-separated fields, one line per worktree, in this
order. Treat the order as a stable contract:

```
task  repo  branch  path  state  ahead  behind  upstream  pr  pr_state  landed  env
```

`landed` is `merged`, `gone`, `new`, `open`, or `-` for an env task. `env` is
`1` or `0`.

## task-retire

    scripts/task-retire [options] [<task>]

          --force      retire despite an env task, uncommitted work, unpushed
                       commits, a lock, a detached HEAD, or a failing hook
          --no-fetch   do not fetch before judging "unpushed"
          --no-hooks   skip .workflow/pre-retire
      -y, --yes        assume yes to the prompt

Retires a whole task; there is no partial retire. With no `<task>`, it
retires the task holding the current directory. It prints the archive path.

1. **Checks every worktree** and lists every problem at once: dirty,
   commits on no origin ref, locked, detached HEAD, or an env task. Any
   problem stops it, and nothing changes.
2. **Asks** for confirmation.
3. **Runs every `pre-retire` hook.** If one fails, it stops before
   anything is removed. A re-run runs the hooks again, so make them safe
   to repeat.
4. **Removes the worktrees and their local branches.** It uses
   `git branch -D`: step 1 proved every commit is on origin, and `-d` would
   refuse a squash-merged branch. The default branch and env branches are
   never deleted.
5. **Archives the task folder.** Plan symlinks are replaced with real
   copies, and a worktree's own `.claude/plans/` is rescued into
   `tasks/<task>/.claude/plans/<repo>/` first. What is left of the folder
   moves to `archive/<task>/`. If that name is taken, the date is appended;
   it never merges into an existing archive.

It never deletes the remote branch. That is your host's delete-on-merge
setting.

## task-prune

    scripts/task-prune [options] [<task>...]

          --yes        retire the candidates (default: dry run)
          --no-fetch   do not fetch; landing and [gone] may be stale
          --force      pass --force through to task-retire

**It is a dry run without `--yes`.** It fetches each repository, then gives
every task a verdict and hands the `retire` ones to `task-retire`.

A repository has **landed** when its pull request is merged, its branch is
merged into the default branch, or its remote branch is gone. A task has
landed only when every repository has.

| verdict | meaning | with `--yes` |
| --- | --- | --- |
| `retire` | every repository landed | retired |
| `partial` | some repositories landed | kept |
| `review` | landed, but commits are on no origin ref and no PR says merged | kept; use `task-retire --force` |
| `skip` | landed, but a worktree is dirty, locked or missing | kept |
| `env` | an env task | kept |
| `keep` | nothing landed yet, or no worktrees | kept |

`review` is the squash-merge case: the squashed commit is a different
object, so every commit on the branch looks unpushed. Only a merged pull
request settles that, so without `gh` a squash-merged task needs your
judgement.

The verdict table goes to stderr. stdout carries only the archive paths of
the tasks it retired.

## sync-repos

    scripts/sync-repos [options] [<repo>...]

      --no-prune      do not pass --prune to fetch
      --no-tags       do not fetch tags
      --fail-fast     stop at the first failure
      --no-ff         do not fast-forward env-task worktrees

Fetches every bare repository, so `origin/*` is current for new tasks. Then,
for the repositories it just fetched, it fast-forwards each env-task
worktree that is clean and behind `origin/<branch>`. It never merges,
rebases or resets:

- **Dirty** or **diverged** worktrees are skipped with a warning.
- **Ahead** worktrees are skipped, with a reminder to push.
- **Feature tasks** are never touched.

Only a failed fetch or fast-forward sets exit code 7.

## Env tasks (optional)

An env task is a long-lived task for running a deployment environment
locally. Both are optional; create them only if you need them:

- **`tasks/main/`** mirrors **production** (branch `main`).
- **`tasks/dev/`** mirrors the **development server** (branch `dev`).

```bash
scripts/task-create main app api   # production
scripts/task-create dev app api    # development server
```

A branch is an env branch when it is listed in `ENV_BRANCHES` in
`workspace.conf`. Without that key, the env branches are each repository's
default branch plus `main`, `master`, `dev`, `develop`, `staging` and
`production`.

| command | with an env task |
| --- | --- |
| `task-create` | checks out the existing branch, tracking `origin/<branch>`; never creates it |
| `task-list` | marks it `env`; never counts it as landed |
| `task-retire` | refuses without `--force`; keeps the branch |
| `task-prune` | never retires it |
| `sync-repos` | fast-forwards its clean worktrees |

## workspace.conf

Optional, and not shipped: create it when you need it. It is a bash file
the scripts source, so it can hold comments.

```bash
# workspace.conf
ENV_BRANCHES="main dev staging"
```

| key | default | meaning |
| --- | --- | --- |
| `ENV_BRANCHES` | each repository's default branch, plus `main master dev develop staging production` | space-separated env branches; setting it replaces the whole default |

## shared/<repo>/

Ignored local files that every new worktree of `<repo>` needs, such as
`.env`. `task-create` copies the tree into each new worktree, keeping
relative paths, before `post-create` runs. It never overwrites a file that
is already there.

A copied path that the repository does not ignore triggers a warning: it
would show as untracked, and a dirty worktree blocks `task-retire`. Ignore
it in the repository, or remove it from `shared/<repo>/`.

## Lifecycle hooks

Branch setup differs per repository, so the scripts call hooks instead of
knowing anything about your database.

Put them in `.workflow/` in the repository and **commit them**. The hook
then travels with the branch and reaches every worktree and every teammate.
Hooks run only from the worktree itself: a bare clone has no files to fall
back to.

| hook | when | on failure |
| --- | --- | --- |
| `post-create` | after the worktree exists and `shared/` is copied | exits 5, leaves the worktree alone |
| `pre-retire` | before any worktree of the task is removed | aborts the retire, exits 5 |

`post-create` does not roll back, because a valid checkout should survive a
transient setup error. Fix the hook and run it by hand, or re-run
`task-create`. `pre-retire` does abort, because it is the only chance to
tear down branch resources.

Hooks run with the worktree as the working directory, through their own
shebang, with output uncaptured so interactive prompts work. A hook that
exists but is not executable produces a warning, never a silent skip.

| variable | example |
| --- | --- |
| `WORKFLOW_EVENT` | `post-create` |
| `WORKFLOW_ROOT` | `/home/me/workspace` |
| `WORKFLOW_TASK` | `feat-login` |
| `WORKFLOW_TASK_DIR` | `/home/me/workspace/tasks/feat-login` |
| `WORKFLOW_REPO` | `app` |
| `WORKFLOW_REPO_DIR` | `/home/me/workspace/repos/app.git` |
| `WORKFLOW_WORKTREE` | `/home/me/workspace/tasks/feat-login/app` |
| `WORKFLOW_WORKTREE_NAME` | `feat-login` |
| `WORKFLOW_BRANCH` | `feat/login` |
| `WORKFLOW_SCOPE` | `feat` |
| `WORKFLOW_SLUG` | `login` |
| `WORKFLOW_BASE_BRANCH` | `main`, on `post-create` only |
| `WORKFLOW_FORCE` | `0` or `1`, on `pre-retire` only |

A branch database is conventionally `${WORKFLOW_REPO}_${WORKFLOW_SLUG}`.

```bash
# .workflow/post-create, committed in the app repository
#!/usr/bin/env bash
set -euo pipefail

db="${WORKFLOW_REPO}_${WORKFLOW_SLUG}"
createdb "$db" 2>/dev/null || true
pg_dump --no-owner "${WORKFLOW_REPO}_dev" | psql --quiet "$db"
printf 'DATABASE_URL=postgres://localhost/%s\n' "$db" >> .env
bun install
```

```bash
# .workflow/pre-retire, committed in the app repository
#!/usr/bin/env bash
set -euo pipefail

dropdb --if-exists "${WORKFLOW_REPO}_${WORKFLOW_SLUG}"
```

Make both executable before committing: `chmod +x .workflow/*`.

## Task notes

Nothing in a task folder outside the worktrees is authoritative, reviewed or
current. It is working material: `NOTES.md`, research, handoffs, and the
task's plan links in `.claude/plans/`. Notes that span tasks go in `docs/`.

`task-retire` moves the folder to `archive/<task>/`, with plan links turned
into real files. Keep the archive for the reasoning, not the answer.
Anything that stabilises belongs in a repository, as documentation or an
ADR.
