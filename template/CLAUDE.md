# Workspace

This directory is scaffolding, not a git repository. The code lives in bare
clones under `repos/<name>.git` and in the worktrees under `tasks/` and
`branches/`. See `references/workspace.md` for the layout and the scripts.
Use the terms as defined in `references/workspace-glossary.md`.

## Three CLAUDE.md files

Each one does a different job, and each loads at a different time.

- **This file:** the workspace root. Placement rules for the task workflow.
  It carries no project domain knowledge. It sits above every task folder,
  so every session in the workspace loads it at start.
- **`tasks/<task>/CLAUDE.md`:** written once by `scripts/task-create`. It
  names the task's branch and where its notes and plans go. A session
  started in the task folder loads it at start.
- **`tasks/<task>/<repo>/CLAUDE.md`:** the product repository's own file.
  It carries the domain rules and travels with every branch. It sits below
  the task folder, so it loads only once the session reads a file in that
  worktree. Read it before planning work that touches that repository.

## Where sessions run

Start Claude in `tasks/<task>/`. From there one session sees every
repository of the task, its `NOTES.md` and its plans. Run cross-task work,
such as a spec that spans several tasks, from the workspace root.

The task folder is not a git repository, which changes how git works there:

- **No git context.** The session starts without a branch, status or recent
  commits. `tasks/<task>/CLAUDE.md` names the branch.
- **Run git as `git -C <repo> …`** from the task folder, once per worktree,
  for example `git -C app status`.
- **Review commands** such as `/code-review`, `/security-review` and
  `/code-review ultra` need a repository as the current directory. `cd` into
  the worktree first, and run one review per repository.

The task's `.claude/settings.json` lets its session write `../../docs/` and
`../../.claude/plans/` and run `../../scripts/` without prompting, once the
task folder is trusted: accept the trust prompt on its first start. The
root `.claude/settings.json` does not apply in task sessions; put shared
settings in each task's file or in user settings. See "Claude Code
settings" in `references/workspace.md`.

Auto-memory and session history belong to the task folder: the next task
does not see them, and retiring the task orphans them. Write anything worth
keeping to the repository's `CLAUDE.md` or docs, or to `docs/`, not to
memory. See "Claude state per task" in `references/workspace.md`.

## Placement by lifetime

A worktree is disposable: `scripts/task-retire` removes it. Anything that
must outlive the branch is written somewhere else.

| Artifact | Goes to | Reaches | On retire |
| --- | --- | --- | --- |
| ADRs, glossary, repo docs | the repository, committed | every branch, and the PR | stays in the repo |
| Task notes, research, handoffs | `tasks/<task>/NOTES.md`, or files beside it | the task's session | moves to `archive/<task>/` |
| Drafts for the user to read, such as PR summaries | `tasks/<task>/drafts/` | the user | moves to `archive/<task>/` |
| Generated files worth keeping: scripts, data, reports | `tasks/<task>/generated/` | the task's session | moves to `archive/<task>/` |
| Plan links | `tasks/<task>/.claude/plans/` | the task's session | copied as real files into `archive/<task>/` |
| Cross-task notes, specs, plans | `docs/`, `.claude/plans/` | every session | stays |
| Ignored local files, such as `.env` | `shared/<repo>/` | every new worktree of `<repo>` | stays |
| A branch to run or review, such as `main` | `branches/<name>/`, via `scripts/branch-add` | that checkout only | `scripts/branch-remove` deletes it |
| Branch setup: database, dependencies | `.workflow/` in the repository, committed | every worktree, via `post-create` | `pre-retire` tears it down |
| Code | the worktree, committed | the branch | the branch lives on origin |

The task folder sits above its worktrees. That is why notes and plans kept
there survive `git worktree remove`, which deletes a worktree's ignored
files without counting them as changes.

## Drafts and generated files

In a workspace, `drafts/` means `tasks/<task>/drafts/`. This overrides any
rule that puts `drafts/` at a repository root: there it would sit inside a
worktree and be deleted on retire. The task folder is not in a repository,
so neither folder needs a gitignore or `info/exclude` entry.

- **`drafts/`:** text the user reviews and pastes elsewhere. Name PR
  summaries per repository, `PR_SUMMARY-<repo>.md`, since one task opens
  one PR per repository.
- **`generated/`:** outputs that stay with the task and are reused, such
  as scripts, data exports and reports. Promote a file into a repository
  and commit it once it earns a permanent place.
- **Neither:** throwaway working files go in the session's scratchpad.

## Plan links

This file pins the destination for plan links: `tasks/<task>/.claude/plans/`
for a task's plans, and `.claude/plans/` at the workspace root for
cross-task plans. Never link a plan into a worktree's own `.claude/plans/`.

The state directories (`completed/`, `paused/`, ...) sit inside that
destination unchanged.

`scripts/task-retire` replaces every link with a real copy of its target
before it archives the task, because Claude Code deletes plan-mode files
after 30 days. As a safety net, it also copies a worktree's own non-empty
`.claude/plans/` into `tasks/<task>/.claude/plans/<repo>/` first.

## One task per unit of work

A task is one branch name across every repository it touches.

1. `scripts/task-create <branch> <repo>...`, then `cd` into the printed
   path and start Claude there. Add a repository later with
   `scripts/task-add <task> <repo>`.
2. Work and commit in each worktree. Keep notes in `NOTES.md`.
3. Push the branch and open one PR per repository.
4. After the merges, run `scripts/task-retire` from inside the task. Or let
   `scripts/task-prune` retire every task that has landed. It is a dry run
   until you pass `--yes`.
5. Run `scripts/sync-repos` so new tasks start from current refs.

`scripts/task-list` shows every task, its repositories, and how far each
one has landed.

## Branch checkouts (optional)

`branches/` holds long-lived checkouts of branches you run or review, not
work on. It is created by the first `scripts/branch-add`:

- `branches/main/` mirrors production.
- `branches/dev/` mirrors the development server.
- `branches/feat-x/` is a teammate's branch, checked out to try it.

Create one with `scripts/branch-add <branch> <repo>...`; the branch must
already exist. `scripts/sync-repos` fast-forwards clean checkouts, and
`scripts/branch-remove` removes one. `task-create` refuses env branches
such as `main` and points here.

A checkout is not a task. It has no `NOTES.md`, no plans and no archive.
Never do feature work or write notes there: start a task with
`scripts/task-create` instead.
