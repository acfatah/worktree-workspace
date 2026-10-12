# Workspace glossary

The terms the scripts, `CLAUDE.md` and `workspace.md` use, each with one
meaning. This file is replaced on upgrade, so keep your own project's terms
in its repository.

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
- **Workspace** — this directory, copied from the template. It holds the
  scripts, the bare clones, the tasks, the branch checkouts and the
  archive. It is not a git repository.
- **`workspace.conf`** — optional settings, a bash file the scripts
  source. Today it has one key, `ENV_BRANCHES`.
- **Worktree** — a git worktree: a working directory for one branch of one
  repository, at `tasks/<task>/<repo>` or `branches/<name>/<repo>`.
  Disposable; anything that must survive it is written elsewhere.
