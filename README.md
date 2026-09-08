# Workflow Using Worktree

Comprehensive Workflow Guide on using Git Worktree for Development with AI Integration.

## Quick Start

Create a new directory then run the following command to set up the workflow template:

```bash
bunx gitpick acfatah/workflow-using-worktree/tree/main/template .
```


## Directory Structure

After running the Quick Start command, the workspace looks like this:

```
project-root/
├── CLAUDE.md         # Placement rules for the worktree workflow.
├── docs/             # Documentation for this workspace.
├── repos/            # Main clone of each repository.
├── scratch/          # Working notes and temporary files.
├── scripts/          # Worktree creation, retirement, and repo sync.
├── skills-lock.json  # Pinned agent skills.
└── worktrees/        # One worktree per branch, per repo.
```

`docs/` and `worktrees/` are created on first use. In this repository the
same tree lives under `template/`, which is what `gitpick` copies.

## Workflow Steps

### 1. Create a Worktree

- Run: `scripts/worktree-create <repo> <scope/branch-name>`
- Purpose: Isolate development in a dedicated directory under `worktrees/<repo>/<scope-branch-name>`.
- Benefit: Keeps the main repo clean while allowing parallel feature or bugfix development.

### 2. Prepare the Database (Optional)

- Dump the remote development database.
- Load it into your local database for consistency.
- Optionally:
  - Create a temporary branch-specific database when schema migrations are required.
  - This avoids breaking other branches and keeps migrations isolated.

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
- Implement changes, run tests, and validate against the local/temporary database.
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
- Run `scripts/worktree-retire` to remove the worktree.
- Run `scripts/sync-repos` to bring `repos/<repo>` up to date.
- Drop temporary databases if used.
- Move the feature's notes from `scratch/active/` to `scratch/archive/`.


## `scratch/` directory

Working notes. Nothing here is authoritative, current, or reviewed.
Files change frequently and may contradict the code.

- inbox/  — unsorted; triage into active/ or delete
- active/ — being worked on now
- parked/ — paused, still relevant
- archive/— done or abandoned; kept for the reasoning, not the answer

Anything that stabilizes moves to docs/ or becomes an ADR.
