# Workspace

This directory is scaffolding. The code lives in `repos/<repo>` and its
worktrees. See README.md for the layout and the scripts.

## Two roots

Two `CLAUDE.md` files exist here and they do different jobs.

- **This file** — the workspace root. Placement rules for the worktree
  workflow. Carries no project domain knowledge.
- **`repos/<repo>/CLAUDE.md`** — the product repo. Carries the
  `## Agent skills` block and the domain rules, and travels with every
  branch.

Run `/setup-matt-pocock-skills` from inside `repos/<repo>`, once per repo.
Run from the workspace root it writes the config where no worktree can
read it.

## Placement by lifetime

A worktree is disposable — `scripts/worktree-retire` deletes it — so
anything that must outlive the branch is written somewhere else.

| Artifact | Goes to | Reaches |
| --- | --- | --- |
| `CONTEXT.md`, `docs/adr/`, `docs/agents/` | `repos/<repo>`, committed | every worktree, and the PR |
| Tickets and specs | the configured issue tracker | every session |
| Grilling notes, research, prototype notes | `scratch/active/<feature>/` | every worktree |
| Code | the worktree, committed | the branch |

Committed docs reach every worktree because they are tracked files on the
branch. `scratch/` reaches every worktree because it sits above all of
them. The worktree reaches nothing but itself.

`/handoff` writes to the OS temp directory by default. Move the file into
`scratch/active/<feature>/` when it should survive the session.

## One ticket, one worktree

`/to-tickets` sizes each ticket to a single fresh context window, which is
also the size of one worktree. Keep them 1:1.

1. `scripts/worktree-create <repo> plan/<feature>`. Run `/grill-with-docs`,
   `/to-spec` and `/to-tickets` in one unbroken context — no `/clear`, no
   `/compact`. Commit the ADR and glossary changes and merge that PR
   first, so every implementation branch starts with them.
2. Per ticket: `scripts/worktree-create <repo> <scope>/<ticket-slug>`,
   `/clear`, then `/implement`. It drives `/tdd` and closes with
   `/code-review`.
3. PR, merge, `scripts/worktree-retire`, `scripts/sync-repos`.

Work the frontier: any ticket whose blockers are all done can take a
worktree, so independent tickets run in parallel worktrees.

## Issue tracker

Prefer a remote tracker (GitHub, GitLab). Tickets have to be readable from
every worktree, and a remote tracker is the only place where that holds by
construction.

The local-markdown option writes `.scratch/<feature>/issues/` inside the
repo, which strands the ticket list on one branch. To use it anyway,
record the shared path in `repos/<repo>/docs/agents/issue-tracker.md` and
link each new worktree to the workspace scratch:

```bash
ln -sfn ../../../scratch/active .scratch
echo .scratch >> "$(git rev-parse --git-path info/exclude)"
```

## Skills

`skills-lock.json` pins the skills this workflow depends on. Restore them
in a fresh checkout with `npx skills experimental_install`.
