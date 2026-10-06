# Workspace

One main clone per repository, one worktree per branch, and a scratch area
that outlives both. See `CLAUDE.md` for where each kind of document belongs.

```
workspace/
├── CLAUDE.md         # placement rules for the worktree workflow
├── docs/             # documentation for this workspace
├── repos/<repo>/     # main clone of each repository
├── scratch/          # working notes: inbox, active, parked, archive
├── scripts/          # the six commands below
├── skills-lock.json  # pinned agent skills
└── worktrees/<repo>/<scope-branch-name>/
```

## Requirements

bash 3.2 or newer, git 2.23 or newer. `gh` is optional: without it the pull
request column and squash-merge detection degrade quietly.

If your copy of the scripts is not executable, run `chmod +x scripts/*`.

## The six commands

| command | what it does |
| --- | --- |
| `scripts/repo-add <url>` | clone a repository into `repos/` |
| `scripts/worktree-create <repo> <scope/branch>` | make a worktree for a branch |
| `scripts/worktree-list` | status of every worktree |
| `scripts/worktree-retire [<repo> <branch>]` | remove a worktree and its branch |
| `scripts/worktree-prune` | retire everything whose work has landed |
| `scripts/sync-repos` | fast-forward every main clone |

Every command takes `-h`. Run them from anywhere: they locate the workspace
from their own path, not from your current directory.

## Conventions

**stdout is payload, stderr is logging.** So this works:

```bash
cd "$(scripts/worktree-create app feat/login)"
```

**Exit codes** are shared across all six commands.

| code | meaning |
| --- | --- |
| 0 | success, including an idempotent no-op |
| 1 | unexpected internal error |
| 2 | usage or validation error |
| 3 | not found: repository, worktree, branch, base |
| 4 | conflicting state: exists, dirty, locked, checked out elsewhere |
| 5 | a lifecycle hook failed |
| 6 | you declined a confirmation |
| 7 | an external tool failed |

**Environment.** `WORKSPACE_ROOT` overrides workspace detection.
`WORKFLOW_YES=1` answers every prompt yes. `WORKFLOW_NO_HOOKS=1` skips
lifecycle hooks. `WORKFLOW_NO_GH=1` forces the no-GitHub path. `NO_COLOR`
and `FORCE_COLOR` work as usual.

## repo-add

    scripts/repo-add [--name n] [--branch b] [--no-skills] [-y] <url> [<name>]

Clones into `repos/<name>`, pins the remote default branch so later commands
can find a base offline, creates `worktrees/<name>/`, and prints the clone
path. Offers to write hook stubs.

Afterwards, configure agent skills **from inside the clone**, never from the
workspace root. It writes to the repository, so every worktree and every pull
request inherits the result.

```bash
cd repos/<name>
npx skills add mattpocock/skills@setup-matt-pocock-skills
```

## worktree-create

    scripts/worktree-create [options] [<repo>] <scope/branch-name>

    -b, --base <ref>   base branch (default: the repository's default branch)
        --no-fetch     do not fetch first
        --no-hooks     skip .workflow/post-create
        --no-env       do not copy ignored local files
        --no-scratch   do not create the .scratch symlink
        --force        reuse an existing empty directory
    -y, --yes          assume yes to prompts

Creates `worktrees/<repo>/<scope-branch-name>`, where slashes in the branch
name become hyphens. `<repo>` may be omitted when the workspace holds one
repository, or when you are already inside `repos/<repo>` or
`worktrees/<repo>`.

It also:

- copies ignored local files matching `.env`, `.env.*`, and `.envrc` from the
  main clone, so a new worktree is not missing its secrets. Override the list
  with `git -C repos/<repo> config --add workflow.copyIgnored '<pattern>'`.
- links `.scratch` to the workspace `scratch/active`, and creates
  `scratch/active/<feature>`.
- runs `repos/<repo>/.workflow/post-create`.

A new branch gets **no upstream** until you `git push -u origin <branch>`.
That is deliberate: inheriting the base branch as upstream breaks `git push`
defaults and makes an untouched branch look merged.

`.env.example` is not copied because it is tracked, so it arrives with the
checkout. Re-running against an existing worktree is a no-op that still
prints the path.

## worktree-list

    scripts/worktree-list [--pr|--no-pr] [--fetch] [--all] [--porcelain] [<repo>...]

One row per worktree: repository, branch, directory, state, ahead and behind
counts, upstream, and pull request. It touches the network only with
`--fetch` or when the pull request column is on.

`--porcelain` emits tab-separated fields in this order, treated as a stable
contract:

```
repo  branch  dirname  path  dirty  ahead  behind  upstream  pr  pr_state
```

## worktree-retire

    scripts/worktree-retire [options] [<repo>] [<branch|dirname>]

        --force         retire despite uncommitted work, unpushed commits, a
                        lock, or a failing pre-retire hook
        --keep-branch   remove the worktree, keep the local branch
        --no-archive    do not move scratch/active/<feature>
        --no-fetch      do not fetch before judging "unpushed"
        --no-hooks      skip .workflow/pre-retire
    -y, --yes           assume yes to prompts

With no arguments it retires the worktree you are standing in. It refuses a
dirty tree or unpushed commits, runs `pre-retire`, copies a non-empty
`.claude/plans/` to `scratch/active/<feature>/plans/`, removes the worktree,
deletes the local branch, and moves `scratch/active/<feature>` to
`scratch/archive/<feature>`. An existing archive is never merged into; a
second one gets a timestamp. The plan copy exists because `.claude/plans/`
is usually git-ignored, and `git worktree remove` deletes ignored files
without counting them as dirty.

`git branch -d` always refuses a squash-merged branch, because the squashed
commit is a different object. When `gh` reports the pull request as merged,
the branch is deleted anyway. Without `gh` you are asked.

It never deletes the remote branch. That is your host's delete-on-merge
setting.

## worktree-prune

    scripts/worktree-prune [--yes] [--no-fetch] [--merged-only] [--gone-only] [--force]

Lists worktrees whose work has landed, then hands each to `worktree-retire`.
**It is a dry run without `--yes`.** A branch counts as landed when its pull
request is merged, when it is merged into the base branch, or when its remote
branch is gone.

Locked, dirty, and missing worktrees are never retired, even with `--yes`. A
branch with unpushed commits is always asked about individually, because
after a squash merge every commit on the branch looks unpushed.

This is not `git worktree prune`. It runs that first, then decides what has
actually been merged.

## sync-repos

    scripts/sync-repos [--no-prune] [--no-tags] [--fail-fast] [<repo>...]

Fetches and fast-forwards every main clone. It never merges, rebases, or
resets, so a repository that has diverged is reported rather than rewritten.
Dirty clones, detached heads, and missing remotes are skipped, not failed.

## Per-repository hooks

Branch setup differs per repository, so the workspace scripts call hooks
instead of knowing anything about your database.

Put them in `repos/<repo>/.workflow/` and **commit them**. That is the point:
the hook then travels with the branch and reaches every worktree and every
teammate. A worktree's own copy wins over the main clone's, so a branch can
change its own setup.

| hook | when | on failure |
| --- | --- | --- |
| `post-create` | after the worktree exists and its files are in place | warns, exits 5, leaves the worktree alone |
| `pre-retire` | before the worktree is removed, while it still exists | aborts the retirement, exits 5 |

`post-create` does not roll back, because a valid checkout should survive a
transient setup error. `pre-retire` does abort, because it is the only chance
to tear down branch resources and it cannot be retried afterwards.

Hooks run with the worktree as the working directory, through their own
shebang, with output uncaptured so interactive prompts work. A hook that
exists but is not executable produces a warning, never a silent skip.

| variable | example |
| --- | --- |
| `WORKFLOW_EVENT` | `post-create` |
| `WORKFLOW_ROOT` | `/home/me/workspace` |
| `WORKFLOW_REPO` | `app` |
| `WORKFLOW_REPO_DIR` | `/home/me/workspace/repos/app` |
| `WORKFLOW_WORKTREE` | `/home/me/workspace/worktrees/app/feat-login` |
| `WORKFLOW_WORKTREE_NAME` | `feat-login` |
| `WORKFLOW_BRANCH` | `feat/login` |
| `WORKFLOW_SCOPE` | `feat` |
| `WORKFLOW_SLUG` | `login` |
| `WORKFLOW_BASE_BRANCH` | `main`, on `post-create` only |
| `WORKFLOW_SCRATCH` | `/home/me/workspace/scratch/active/login` |
| `WORKFLOW_FORCE` | `0` or `1`, on `pre-retire` only |

A branch database is conventionally `${WORKFLOW_REPO}_${WORKFLOW_SLUG}`.

```bash
# repos/app/.workflow/post-create
#!/usr/bin/env bash
set -euo pipefail

db="${WORKFLOW_REPO}_${WORKFLOW_SLUG}"
createdb "$db" 2>/dev/null || true
pg_dump --no-owner "${WORKFLOW_REPO}_dev" | psql --quiet "$db"
printf 'DATABASE_URL=postgres://localhost/%s\n' "$db" >> .env
bun install
```

```bash
# repos/app/.workflow/pre-retire
#!/usr/bin/env bash
set -euo pipefail

dropdb --if-exists "${WORKFLOW_REPO}_${WORKFLOW_SLUG}"
```

## scratch/

Working notes. Nothing here is authoritative, current, or reviewed. Files
change frequently and may contradict the code.

- `inbox/` — unsorted; triage into `active/` or delete
- `active/` — being worked on now; reachable from every worktree as `.scratch`
- `parked/` — paused, still relevant
- `archive/` — done or abandoned; kept for the reasoning, not the answer

Anything that stabilizes moves to `docs/` or becomes an ADR.
