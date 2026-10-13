# Worktree Workspace

A workspace scaffold for multi-repository development with git worktrees and
AI agents. Each repository is a bare clone. Each task is one folder holding
a worktree of every repository it touches, all on one branch, plus the
task's notes and plans. One agent session, started in the task folder, sees
all of it.

## What This Is and What It Isn't

It is:

- **A copied scaffold:** a folder layout plus ten bash scripts that you
  copy once and then own.
- **One task, one branch across repositories:** a task folder holds a
  worktree of each repository on the same branch, plus its notes and plans.
- **An agent-friendly layout:** one session started in the task folder sees
  every repository. Placement rules live in `CLAUDE.md`.
- **A safe lifecycle:** `task-retire` checks for dirty or unpushed work
  before it changes anything, and archives the notes. The commands are
  idempotent and resumable.

It isn't:

- **A git or GitHub wrapper:** you still commit, push and open the PRs
  yourself. `gh` is optional and only reads PR state.
- **A Claude Code plugin:** it adds no hooks and changes no model setting,
  and the scripts run without any agent. See
  [Effects on Claude Code](#effects-on-claude-code).
- **An installed tool:** there is no package and no auto-update. Upgrades
  are manual; see [Upgrading a Workspace](#upgrading-a-workspace).
- **A monorepo or build tool:** it sets up no sparse checkout, shared
  install or build cache. See [Monorepos](#monorepos) for the cost.
- **A wrapper around your existing clone:** it replaces the clone. See
  [Adopting an Existing Project](#adopting-an-existing-project).
- **A deploy or environment manager:** `branches/main` runs production
  locally, but nothing deploys or provisions. Write any setup you need as
  [lifecycle hooks](#2-prepare-branch-resources-optional).
- **Claude Code's `--worktree`:** that gives one throwaway worktree per
  session in one repository. This workspace gives one task folder across
  repositories. Do not mix the two; see the
  [Effects on Claude Code](#effects-on-claude-code) table.

It is a good fit for:

- **Work that spans repositories**, such as a client and a server change
  that ship together.
- **Several branches in flight at once**, side by side, without stashing.
- **Agent sessions that need every repository** of a change.
- **Per-branch databases and ports**, set up by hooks.

It is a poor fit for:

- **A one-line fix in a single repository:** a plain clone is quicker.
- **Windows without bash:** the scripts need bash 3.2 or newer, for
  example through WSL.
- **A team that needs sparse checkouts** of a huge monorepo: every task is
  a full checkout.

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

## Compatibility

The workflow, and the agent rules in its `CLAUDE.md` files, were built and
tested with Claude Code running Claude Opus 5. Other models, other
providers, and other agent harnesses may follow the rules differently, or
not at all, so the same results are not guaranteed there. The scripts
themselves are plain bash and git and do not depend on any agent.

## Directory Structure

After running the Quick Start command and adding two repositories, the
workspace looks like this:

```
project-root/               # a plain folder
├── CLAUDE.md               # Placement rules for the task workflow.
├── archive/                # Folders of retired tasks.
├── branches/               # Optional branch checkouts, made on request.
├── docs/                   # Cross-task notes, specs and diagrams.
├── references/             # Script reference and glossary.
├── repos/
│   ├── client.git/         # Bare clone.
│   └── server.git/         # Bare clone.
├── scripts/                # Task lifecycle, repo sync, and status.
├── shared/<repo>/          # Ignored local files (.env) for new worktrees.
└── tasks/
    └── feat-login/         # A task, on branch feat/login.
        ├── NOTES.md        # The task's notes, beside its plans.
        ├── client/         # Worktree.
        └── server/         # Worktree.
```

The [full layout](template/references/workspace.md#workspace) lists every
file the workspace and each task folder hold.

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
  `feat/login`, plus the task's own files; see
  [task-create](template/references/workspace.md#task-create).
- It prints the path, so `cd "$(scripts/task-create feat/login client)"`
  puts you straight into the task.
- Need another repository later? `scripts/task-add feat-login server`.

### 2. Prepare Branch Resources (Optional)

When each branch needs its own setup, such as a database, a dependency
install or a port, write it as a `post-create` hook in `.workflow/` in the
repository and commit it. Every worktree of that repository then gets the
same treatment, and teammates inherit it. The hook runs inside the new
worktree, after the `shared/` files are copied.

The usual case is a branch database. Every worktree gets its own copy of
`shared/<repo>/.env`, so the hook can create a database for the task and
point that copy's `DATABASE_URL` at it, without touching any other task.
Schema migrations on the branch then cannot break the others. A matching
`pre-retire` hook drops the database when step 6 retires the task.

The reference has the
[hook contract](template/references/workspace.md#lifecycle-hooks) and a
[complete example](template/references/workspace.md#per-branch-values-in-env)
of both hooks.

### 3. Plan in the Task Folder

Start your agent in `tasks/<task>/`. One session then sees every
repository of the task.

Keep the task's working material, such as notes and plans, in the task
folder. It sits above the worktrees, so it survives them, and step 6
archives it. Notes that span tasks go in `docs/`. Commit the plans that
stabilise into the repository, as documentation or an ADR. `CLAUDE.md` has
the full placement table, and
[Task notes](template/references/workspace.md#task-notes) lists what a
task folder holds.

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
- It checks every worktree first. If any could lose work, it lists the
  problems and changes nothing.
- It runs every `pre-retire` hook, removes the worktrees and their local
  branches, and moves the task folder to `archive/<task>/`. Plan links
  become real files on the way.
- [task-retire](template/references/workspace.md#task-retire) lists the
  checks and the options to override them.

### 7. Housekeeping

- `scripts/task-list` shows every task and the state of each repository,
  including how far it has landed. A task where only some repositories
  landed shows `landed 1/2`. See
  [task-list](template/references/workspace.md#task-list) for the columns.
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
`branch-add`, so `tasks/` only ever holds units of work. To change which
branches count as env branches, set `ENV_BRANCHES` in `workspace.conf`;
see [Env branches](template/references/workspace.md#env-branches) for the
defaults.

## Effects on Claude Code

The workspace adds no Claude Code hooks and changes no model or harness
setting. Its `.workflow/` hooks are git-side scripts that the `task-*`
commands run. Each task's generated `.claude/settings.json` only adds
directories and one allow rule.

A task folder is not a git repository, though, and Claude Code keys much of
its state on the folder a session starts in. Starting Claude in
`tasks/<task>/` therefore changes some defaults:

| Area | Claude Code default | In a task folder | What to do |
| --- | --- | --- | --- |
| Git context | Branch, status and recent commits in the prompt | None: the task folder is not a repository | Run `git -C <repo> …`; the task's `CLAUDE.md` names the branch |
| Review commands | Run in the current folder | Fail at the task level | `cd` into each worktree and run one review per repository |
| Built-in worktrees | `claude --worktree`, `EnterWorktree`, `isolation: "worktree"` | Fail, or land under `repos/<repo>.git/.claude/worktrees/` | Don't use them; start another task with `task-create` |
| Project settings | Read from the launch folder | The root `.claude/settings.json` is ignored | Use each task's file, or user settings |
| Trust prompt | Once per project | Once per task folder | Accept it on each new task, or `git init` the workspace root |
| Auto-memory | Per project | Per task folder, orphaned on retire | Keep lasting knowledge in the repository or `docs/` |
| Session history | Per folder | Leaves `/resume` once the folder is archived | Use `claude --resume <session-id>` |
| Saved approvals | Per project | Per task | Put standing permissions in settings files |

The reference explains each row under
[Claude Code settings](template/references/workspace.md#claude-code-settings),
including the `git init` tip, and
[Claude state per task](template/references/workspace.md#claude-state-per-task).

## Compared With Alternatives

**Plain clones and `git switch`** are simpler, with nothing to learn. But
switching branches means stashing work and often reinstalling
dependencies, and each repository stays separate. A task folder keeps
branches side by side and groups the repositories of one change.

**Generic worktree managers** are lighter and need no folder convention.
Most of them handle one repository at a time. This workspace adds tasks
that span repositories, notes that outlive the worktrees, a safety check
before retiring, and detection of landed work.

**Monorepo tooling such as Turborepo or Nx** is a complement, not a
competitor. It owns builds and caching, while the workspace only owns
checkouts. See [Monorepos](#monorepos) for the cost each task adds.

## Adopting an Existing Project

The workspace replaces your existing clone; it does not wrap it. Create it
next to the clone, never inside it. A `ws-` prefix tells it apart from a
regular clone at a glance.

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
   [Env branches](template/references/workspace.md#env-branches)).
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

## Upgrading a Workspace

The workspace is copied, not installed, so it never updates itself. You
upgrade by copying the parts that ship from the template and leaving the
parts you own alone.

### Steps

1. **Read what changed** in the
   [history of `template/`](https://github.com/acfatah/worktree-workspace/commits/main/template).
   Commits marked `!`, such as `feat(scripts)!:`, are breaking.
2. **Fetch the new template** into a temporary folder outside the
   workspace:

   ```bash
   tmp=$(mktemp -d)
   bunx gitpick acfatah/worktree-workspace/tree/main/template "$tmp/template"
   ```

3. **Replace `scripts/` and `references/` completely.** Remove them, then
   copy the new ones, so a script deleted upstream goes too. Run this from
   the workspace root:

   ```bash
   rm -rf scripts references
   cp -R "$tmp/template/scripts" "$tmp/template/references" .
   chmod +x scripts/*
   ```

4. **Diff and merge** the root `CLAUDE.md` and `.vscode/settings.json`.
   They may hold your own edits, so never overwrite them:

   ```bash
   diff "$tmp/template/CLAUDE.md" CLAUDE.md
   diff "$tmp/template/.vscode/settings.json" .vscode/settings.json
   ```

5. **Leave everything else alone:** `README.md`, `workspace.conf`,
   `repos/`, `tasks/`, `branches/`, `archive/`, `docs/` and `shared/` are
   yours. Then remove the temporary folder: `rm -rf "$tmp"`.

### Existing Tasks

Existing tasks keep the `CLAUDE.md` and `.claude/settings.json` that the
old `task-create` wrote; only new tasks get the new ones. If the
difference matters for a task, edit those two files by hand, or retire the
task and create it again.

### Letting an Agent Upgrade

Start your agent in the workspace root and paste this prompt, with your
own value in place of the placeholder:

```text
Upgrade this worktree workspace to the latest template. Follow
"Upgrading a Workspace" in the workspace guide at
https://github.com/acfatah/worktree-workspace#upgrading-a-workspace

- Last upgrade or scaffold: <date | commit>

Rules:
- Read the history of template/ since that point and summarise the
  breaking changes (commits marked `!`) before changing anything.
- Replace scripts/ and references/ completely from a fresh template
  fetched into a temporary folder.
- Show me the diff of the root CLAUDE.md and .vscode/settings.json and
  wait for my approval before merging either one.
- Never touch repos/, tasks/, branches/, archive/, docs/, shared/,
  README.md or workspace.conf.
- Finish with `scripts/task-list` and a summary of what changed and
  anything I still need to do, such as updating existing tasks.
```

## Glossary

The workspace terms, such as task, landed and retire, are defined in
[template/references/workspace-glossary.md](template/references/workspace-glossary.md).
It ships with every workspace as `references/workspace-glossary.md`.
