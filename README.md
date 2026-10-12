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

Moving a project you already have cloned? See
[Adopting an Existing Project](#adopting-an-existing-project).

## Directory Structure

After running the Quick Start command and adding two repositories, the
workspace looks like this:

```
project-root/               # a plain folder, not a git repository
├── CLAUDE.md               # Placement rules for the task workflow.
├── README.md               # Yours: describe the workspace.
├── .claude/plans/          # Cross-task plan links.
├── archive/                # Notes and plans of retired tasks.
├── branches/               # Optional branch checkouts, made on request.
│   ├── main/               # Production.
│   │   ├── client/
│   │   └── server/
│   └── dev/                # Development server.
├── docs/                   # Cross-task notes, specs and diagrams.
├── references/             # Workspace guide, script reference and glossary.
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
│       ├── .claude/settings.json  # Generated: reach docs/ and scripts/.
│       ├── client/         # Worktree.
│       └── server/         # Worktree.
└── workspace.conf          # Optional; created when you need it.
```

In this repository the same tree lives under `template/`, which is what
`gitpick` copies. The workspace's `references/workspace.md` documents every
command, its options, and the per-repository hooks; this page is the tour.
The workspace's root `README.md` is a stub for you to describe your own
workspace.

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
  `feat/login`, plus `CLAUDE.md`, `NOTES.md`, `.claude/plans/` and
  `.claude/settings.json`.
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
step 6 runs. The workspace's `references/workspace.md` has the full hook
contract and the matching `pre-retire`.

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

## Adopting an Existing Project

The workspace replaces your existing clone; it does not wrap it. Create it
next to the clone, never inside: the workspace must not be a git repository.
A `ws-` prefix tells it apart from a regular clone at a glance.

```
~/work/acme/        # your existing clone; retire it at the end
~/work/ws-acme/     # the new workspace
```

### Steps

1. **Scaffold** the workspace with the Quick Start command.
2. **Add each repository by its real remote URL**:
   `scripts/repo-add git@github.com:org/acme.git`. Not the path of your
   local clone: `origin` would point at it, so pushes land on your disk and
   pull requests are never found.
3. **Move ignored local files**, such as `.env`, into `shared/<repo>/`,
   keeping their relative paths. Each must be ignored by the repository, or
   it makes every worktree dirty and blocks `task-retire`.
4. **Bring over branches in progress.**
   - Pushed: `scripts/task-create feat/x acme` picks up `origin/feat/x`.
   - Not pushed: push it from the old clone into the bare clone, then
     create the task. Push it to origin before you retire the task.

     ```bash
     git -C ~/work/acme push ~/work/ws-acme/repos/acme.git feat/x:feat/x
     scripts/task-create feat/x acme
     ```

5. **Bring over uncommitted changes** on the branch the old clone has
   checked out. First pick where they go:
   - **A feature in progress** belongs in a task, even if you started it on
     `main`. Move it to its own branch in the old clone first, with
     `git switch -c feat/x`; the changes come along.
   - **Local tweaks to an env branch**, such as config for running
     production locally, go to a branch checkout: `branches/main/`.

   Then carry them over as a stash. The commands below move changes on
   `main` into `branches/main/`. For a task, use `task-create` and the
   task's worktree instead.

   ```bash
   old=~/work/acme ws=~/work/ws-acme
   git -C "$old" stash push -u -m migrate
   git -C "$old" push "$ws/repos/acme.git" 'stash@{0}:refs/migrate/main'
   git -C "$old" stash pop --index      # the old clone is as it was
   "$ws/scripts/branch-add" main acme
   git -C "$ws/branches/main/acme" stash apply --index refs/migrate/main
   git -C "$ws/branches/main/acme" update-ref -d refs/migrate/main
   ```

   Staged, unstaged, untracked and deleted files all move, and staged
   changes stay staged. Ignored files do not; those belong in `shared/`.
   Move unpushed commits on the branch first, as in step 4, so the stash
   applies to the commit it was made on. If the new worktree is at a
   different commit, `stash apply` merges and may stop with conflicts.

6. **Commit lifecycle hooks** to the repository if branches need setup,
   such as a dependency install or a branch database. See step 2 of
   [Workflow Steps](#2-prepare-branch-resources-optional).
7. **List your env branches** in `workspace.conf` if they differ from the
   defaults (see
   [Env branch](template/references/workspace-glossary.md)).
8. **Recreate local git config** that lived only in the old clone, such as
   `core.hooksPath` or a per-repository `user.email`, on
   `repos/<repo>.git`. Its worktrees read that config.
9. **Retire the old clone** once `scripts/task-list` shows every task you
   moved. Nothing in the workspace depends on it.

### Monorepos

A monorepo is a workspace with one repository, and every step above applies:

```bash
scripts/repo-add git@github.com:org/mono.git
cd "$(scripts/task-create feat/login mono)"
```

Task folders, notes, plans, hooks, branch checkouts and `task-prune` all
work. Only the one-branch-across-repositories part has nothing to do. A
monorepo can also share a task with other repositories:
`scripts/task-create feat/x mono infra`.

Budget for the cost per task:

- **A full checkout.** The scripts do not set up sparse checkouts.
- **Its own dependency install.** Install in `post-create`, and prefer a
  package manager with a shared store, such as pnpm or bun, so installs are
  links rather than copies.
- **Its own build cache** for tools such as Turborepo or Nx, unless you point
  the cache at a shared location.

### Parallel Tasks

Two tasks running dev servers at once collide on the same port. Have
`post-create` write a per-task `PORT` into the worktree's `.env`, the same
way it rewrites `DATABASE_URL`.

### Letting an Agent Do It

Start your agent in the new, empty workspace folder and paste this prompt,
with your own values in place of the placeholders:

```text
Adopt my existing project into this worktree workspace. Follow
"Adopting an Existing Project" in the workspace guide at
https://github.com/acfatah/worktree-workspace#adopting-an-existing-project
and references/workspace.md here for the script reference.

- Existing clone(s): <path>, <path>
- Branches to bring over: <all local branches | list>
- Branches that need a per-task database or port: <none | details>

Rules:
- Scaffold this folder first if scripts/ is missing.
- Read each clone's `git remote -v` and use that URL for repo-add.
- Show me the list of files you plan to copy into shared/ and wait for
  my approval.
- Never push to origin and never commit in the repositories without
  asking me first. Leave the old clones as you found them: if you stash
  there, pop it back.
- Ask me where uncommitted changes in each clone should go: a task or a
  branch checkout.
- Finish with `scripts/task-list` and a summary of what moved, what did
  not, and what I still need to do.
```

## Glossary

The workspace terms, such as task, landed and retire, are defined in
[template/references/workspace-glossary.md](template/references/workspace-glossary.md).
It ships with every workspace as `references/workspace-glossary.md`.
