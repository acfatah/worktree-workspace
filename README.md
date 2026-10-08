# Worktree Workspace

A workspace scaffold for multi-repository development with git worktrees and
AI agents. Each repository is a bare clone. Each task is one folder holding
a worktree of every repository it touches, all on one branch, plus the
task's notes and plans. One agent session, started in the task folder, sees
all of it.

## Quick Start

Create a new directory then run the following command to set up the
workspace:

```bash
bunx gitpick acfatah/worktree-workspace/tree/main/template .
```

If the copy did not preserve executable bits, run `chmod +x scripts/*` once.
The scripts need bash 3.2 and git 2.23 or newer; `gh` is optional.

## Directory Structure

After running the Quick Start command and adding two repositories, the
workspace looks like this:

```
project-root/               # a plain folder, not a git repository
├── CLAUDE.md               # Placement rules for the task workflow.
├── README.md               # Workspace guide and the full script reference.
├── .claude/plans/          # Cross-task plan links.
├── archive/                # Notes and plans of retired tasks.
├── branches/               # Optional branch checkouts, made on request.
│   ├── main/               # Production.
│   │   ├── client/
│   │   └── server/
│   └── dev/                # Development server.
├── docs/                   # Cross-task notes, specs and diagrams.
├── repos/
│   ├── client.git/         # Bare clone.
│   └── server.git/         # Bare clone.
├── scripts/                # Task lifecycle, repo sync, and status.
├── shared/<repo>/          # Ignored local files (.env) for new worktrees.
├── tasks/
│   └── feat-login/         # A task, on branch feat/login.
│       ├── CLAUDE.md       # Generated: the branch, where notes go.
│       ├── NOTES.md        # Generated stub.
│       ├── .claude/plans/  # This task's plan links.
│       ├── client/         # Worktree.
│       └── server/         # Worktree.
└── workspace.conf          # Optional; created when you need it.
```

In this repository the same tree lives under `template/`, which is what
`gitpick` copies. The workspace's own `README.md` documents every command,
its options, and the per-repository hooks; this page is the tour.

## Workflow Steps

### 0. Add the Repositories

- Run: `scripts/repo-add <url>`, once per repository.
- It makes a bare clone at `repos/<name>.git` and pins its default branch.
- Put ignored local files that every worktree needs, such as `.env`, in
  `shared/<name>/`.

### 1. Create a Task

- Run: `scripts/task-create <branch> <repo>...`, for example
  `scripts/task-create feat/login client server`.
- It creates `tasks/feat-login/` with a worktree of each repository on
  `feat/login`, plus `CLAUDE.md`, `NOTES.md` and `.claude/plans/`.
- It prints the path, so `cd "$(scripts/task-create feat/login client)"`
  puts you straight into the task.
- Need another repository later? `scripts/task-add feat-login server`.

### 2. Prepare Branch Resources (Optional)

Put this in `.workflow/post-create` in the repository and commit it, so
every worktree of that repository gets the same treatment and teammates
inherit it. The hook runs inside the new worktree, after the `shared/`
files are copied, with the task and branch details in the environment.
`${WORKFLOW_REPO}_${WORKFLOW_SLUG}` is the conventional name for a branch
database.

```bash
#!/usr/bin/env bash
# .workflow/post-create
set -euo pipefail

if [ "$WORKFLOW_KIND" = task ]; then   # branch checkouts keep shared values
  db="${WORKFLOW_REPO}_${WORKFLOW_SLUG}"
  createdb "$db" 2>/dev/null || true
  pg_dump --no-owner "${WORKFLOW_REPO}_dev" | psql --quiet "$db"
  grep -v '^DATABASE_URL=' .env > .env.tmp 2>/dev/null || true
  printf 'DATABASE_URL=postgres://localhost/%s\n' "$db" >> .env.tmp
  mv .env.tmp .env
fi
```

Every worktree gets its own copy of `shared/<repo>/.env`, so the hook
rewrites `DATABASE_URL` for this task only; the scripts never edit `.env`
themselves. A branch-specific database keeps schema migrations from
breaking other branches. Tear it down in `.workflow/pre-retire`, which
step 6 runs. The workspace README has the full hook contract and the
matching `pre-retire`.

### 3. Plan in the Task Folder

Start your agent in `tasks/<task>/`. One session then sees every
repository of the task.

Keep the task's working material in the task folder: notes in `NOTES.md`,
plan links in `.claude/plans/`. It sits above the worktrees, so it
survives them, and step 6 archives it. Notes that span tasks go in
`docs/`. Commit the plans that stabilise into the repository, as
documentation or an ADR. `CLAUDE.md` has the full placement table.

Keep one task per unit of work.

### 4. Develop and Commit

- Work in `tasks/<task>/<repo>`, one worktree per repository.
- Keep commits atomic, scoped to the task, with conventional messages
  (`feat:`, `fix:`, `chore:`).
- Run pre-commit hooks or linting checks if configured.

### 5. Open the Pull Requests

- Push the branch in each repository: `git push -u origin <branch>`.
- Open one PR per repository, all from the same branch name, with a clear
  description, migration notes if any, and links to the related PRs.

### 6. Retire the Task

After the PRs merge or close:

- Run `scripts/task-retire` from inside the task, or
  `scripts/task-retire <task>` from anywhere.
- It refuses if any worktree is dirty or holds commits that are on no
  origin branch.
- It runs every `pre-retire` hook, removes the worktrees and their local
  branches, and moves the task folder to `archive/<task>/`. Plan links
  become real files on the way.

### 7. Housekeeping

- `scripts/task-list` shows every task and, per repository, whether it is
  dirty, how far ahead or behind it is, its PR state, and whether it has
  landed. A task where only some repositories landed shows `landed 1/2`.
- `scripts/task-prune` retires every task whose repositories have all
  landed. It is a dry run until you pass `--yes`.
- `scripts/sync-repos` fetches every repository and fast-forwards the
  branch checkouts.

### Branch Checkouts (Optional)

To run a deployment environment locally, or to try a teammate's branch,
check the branch out under `branches/`, apart from your tasks:

- `scripts/branch-add main client server` mirrors **production**.
- `scripts/branch-add dev client server` mirrors the **development
  server**.
- `scripts/branch-add feat/x client` checks out a teammate's branch.

The branch must already exist. `branches/` is created on the first
`branch-add`. `scripts/branch-list` shows each checkout's state,
`sync-repos` keeps the clean ones fast-forwarded, and
`scripts/branch-remove <name>` removes one.

`task-create` refuses an env branch such as `main` and points to
`branch-add`, so `tasks/` only ever holds units of work. List other env
branches in `workspace.conf` as `ENV_BRANCHES="main dev staging"`.

## Glossary

- **Archive** — `archive/<task>/`, where `task-retire` moves what is left
  of a task folder: notes, and plans as real files.
- **Branch checkout** — a long-lived worktree, under `branches/<name>/`,
  of a branch you run or review rather than work on, such as `main` for
  production. Made by `branch-add`, removed by `branch-remove`, kept
  current by `sync-repos`. It has no notes and no archive.
- **Bare clone** — the one clone of a repository, at `repos/<name>.git`,
  with no working files of its own. Every worktree hangs off it, and
  `sync-repos` keeps its `origin/*` refs current.
- **Base branch** — the branch a new task branch starts from. Defaults to
  the repository's default branch, pinned by `repo-add`; override with
  `repo-add --branch` or `task-create --base`.
- **Env branch** — a branch listed in `ENV_BRANCHES`. Without that key,
  each repository's default branch plus `main`, `master`, `dev`,
  `develop`, `staging` and `production`. `task-create` refuses one; check
  it out with `branch-add`. Its local branch is never deleted.
- **Landed** — a repository's branch whose work has reached the default
  branch: its PR is merged, it is merged into the default branch, or its
  remote branch is gone. A task has landed when every repository has.
- **Lifecycle hook** — an executable script in `.workflow/`, committed to
  the repository. `post-create` runs after a worktree is made;
  `pre-retire` runs before a task's worktrees are removed and can abort
  the retire.
- **Plan link** — a symlink to an agent's plan-mode file, kept in
  `tasks/<task>/.claude/plans/` so it outlives the worktrees.
- **Prune verdict** — what `task-prune` decides for a task: `retire`,
  `partial`, `review`, `skip`, `env` or `keep`.
- **Retire** — finish a task for good: run `pre-retire`, delete its
  worktrees and local branches, and archive its folder. Done by
  `scripts/task-retire`.
- **Scope** — the part of a branch name before the first slash, such as
  `feat` in `feat/login`. Empty when the branch has no slash.
- **Shared files** — ignored local files in `shared/<repo>/`, copied into
  every new worktree of that repository.
- **Slug** — the branch name with its scope stripped and any remaining
  slashes turned into hyphens, such as `login` in `feat/login`.
- **Task** — one unit of work: one branch name across every repository it
  touches, in one folder under `tasks/`.
- **Task folder name** — the branch name with every slash turned into a
  hyphen, such as `feat-login`.
- **Workspace** — the directory created by the Quick Start command. It
  holds the scripts, the bare clones, the tasks, the branch checkouts and
  the archive. It is not a git repository.
- **`workspace.conf`** — optional settings, a bash file the scripts
  source. Today it has one key, `ENV_BRANCHES`.
- **Worktree** — a git worktree: a working directory for one branch of one
  repository, at `tasks/<task>/<repo>` or `branches/<name>/<repo>`.
  Disposable; anything that must survive it is written elsewhere.
