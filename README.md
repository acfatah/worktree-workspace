# Worktree Workspace

A workspace scaffold for multi-repository development with git worktree and
AI agents. One main clone per repository, one worktree per branch, and a
scratch area that outlives both.

## Quick Start

Create a new directory then run the following command to set up the
workspace:

```bash
bunx gitpick acfatah/worktree-workspace/tree/main/template .
```

If the copy did not preserve executable bits, run `chmod +x scripts/*` once.
The scripts need bash 3.2 and git 2.23 or newer; `gh` is optional.


## Directory Structure

After running the Quick Start command, the workspace looks like this:

```
project-root/
├── CLAUDE.md         # Placement rules for the worktree workflow.
├── README.md         # Workspace guide and the full script reference.
├── docs/             # Documentation for this workspace.
├── repos/            # Main clone of each repository.
├── scratch/          # Working notes and temporary files.
├── scripts/          # Worktree lifecycle, repo sync, and status.
├── skills-lock.json  # Pinned agent skills.
└── worktrees/        # One worktree per branch, per repo.
```

In this repository the same tree lives under `template/`, which is what
`gitpick` copies. The workspace's own `README.md` documents every command,
its options, and the per-repository hooks; this page is the tour.

## Workflow Steps

### 0. Add a Repository

- Run: `scripts/repo-add <url>`
- Clones into `repos/<name>`, pins its default branch, and creates
  `worktrees/<name>/`.
- Then configure agent skills from inside `repos/<name>`, as step 3 explains.

### 1. Create a Worktree

- Run: `scripts/worktree-create <repo> <scope/branch-name>`
- Purpose: Isolate development in a dedicated directory under
  `worktrees/<repo>/<scope-branch-name>`.
- Benefit: Keeps the main repo clean while allowing parallel feature or
  bugfix development.
- It also copies ignored local files such as `.env`, links `.scratch` to the
  workspace scratch area, and runs the repository's `post-create` hook.
- It prints the path, so `cd "$(scripts/worktree-create app feat/login)"`
  puts you straight into the new worktree.

### 2. Prepare the Database (Optional)

Put this in `repos/<repo>/.workflow/post-create` and commit it, so every
worktree of that repository gets the same treatment and teammates inherit it.
The hook runs inside the new worktree with the branch details in the
environment; `${WORKFLOW_REPO}_${WORKFLOW_SLUG}` is the conventional name for
a branch database.

```bash
# repos/app/.workflow/post-create
db="${WORKFLOW_REPO}_${WORKFLOW_SLUG}"
createdb "$db" 2>/dev/null || true
pg_dump --no-owner "${WORKFLOW_REPO}_dev" | psql --quiet "$db"
printf 'DATABASE_URL=postgres://localhost/%s\n' "$db" >> .env
```

A branch-specific database keeps schema migrations from breaking other
branches. Tear it down in `pre-retire`, which step 7 runs. The workspace
README has the full hook contract.

### 3. Plan Development with AI/Agent

Install the planning skill:

```bash
npx skills add mattpocock/skills@setup-matt-pocock-skills
```

Then run `setup-matt-pocock-skills` **from inside `repos/<repo>`**, once per
repository, to configure its issue tracker, triage label vocabulary, and
domain doc layout. It writes to the repository, so every worktree and every
pull request inherits the result. Running it at the workspace root instead
leaves the configuration where no worktree can read it.

Installed skills are pinned in `skills-lock.json`. To restore them in a fresh
checkout, run `npx skills experimental_install` — the command is still marked
experimental upstream.

Use an AI assistant or planning agent to outline tasks, generate scaffolding,
suggest migration strategies, and track dependencies and risks.

Plans do not live in the worktree, because step 7 deletes it. Put them in
`scratch/active/<feature>/` while they are in flux, and commit the ones that
stabilise into the repository as documentation or an ADR. `CLAUDE.md` has the
full placement table and the session-by-session flow.

### 4. Develop in the Worktree

- Navigate to: `worktrees/<repo>/<scope-branch-name>`
- Implement changes, run tests, and validate against the local or temporary
  database.
- Keep commits atomic and descriptive for easier review.

### 5. Commit Changes

- Follow conventional commit messages (e.g., feat:, fix:, chore:).
- Ensure commits are scoped to the branch purpose.
- Run pre-commit hooks or linting checks if configured.

### 6. Create a Pull Request (PR)

- Push the branch to remote.
- Open a PR with:
  - Clear description of changes.
  - Migration notes if applicable.
  - Links to AI-generated plans or docs.
- Request review from peers or automated agents.

### 7. Retire the Worktree

After PR merge or branch closure:
- Run `scripts/worktree-retire` from inside the worktree, or
  `scripts/worktree-retire <repo> <branch>` from anywhere.
- It runs the repository's `pre-retire` hook, which is where temporary
  databases get dropped, removes the worktree and the local branch, and moves
  the feature's notes from `scratch/active/` to `scratch/archive/`.
- It refuses to run on a dirty worktree or one holding unpushed commits.
- Run `scripts/sync-repos` to bring every `repos/<repo>` up to date.

### 8. Housekeeping

- `scripts/worktree-list` shows every worktree across every repository, with
  its branch, whether it is dirty, how far ahead or behind it is, and its pull
  request state. This is how you see which tickets are still open and which
  frontier is free.
- `scripts/worktree-prune` finds everything whose work has landed and retires
  it in one pass. It is a dry run until you pass `--yes`.
- `scripts/sync-repos` fast-forwards every main clone and never rewrites one.


## `scratch/` directory

Working notes. Nothing here is authoritative, current, or reviewed.
Files change frequently and may contradict the code.

- inbox/  — unsorted; triage into active/ or delete
- active/ — being worked on now
- parked/ — paused, still relevant
- archive/— done or abandoned; kept for the reasoning, not the answer

Anything that stabilizes moves to docs/ or becomes an ADR.
