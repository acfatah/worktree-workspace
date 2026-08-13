# Workflow Using Worktree

Comprehensive Workflow Guide on using Git Worktree for Development with AI Integration.

## Quick Start

Create a new directory then run the following command to set up the workflow template:

```bash
bunx gitpick acfatah/workflow-using-worktree/tree/main/template .
```


## Directory Structure

```
project-root/
├── scratch/        # Contains working notes and temporary files.
├── template/
│   ├── docs/       # Contains documentation for the workflow.
│   ├── repos/      # Contains the main repositories for the project.
│   ├── scripts/    # Contains scripts for automating worktree creation and cleanup.
│   └── worktrees/  # Contains worktrees for different branches and scopes
├── LICENSE
└── README.md
```

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

Install the planning skill once per project:

```bash
npx skills add mattpocock/skills@setup-matt-pocock-skills
```

Then run the `setup-matt-pocock-skills` skill to configure this repository's
issue tracker, triage label vocabulary, and domain doc layout for the rest of
the engineering skills.

Installed skills are pinned in `skills-lock.json`. To restore them in a fresh
checkout, run `npx skills experimental_install` — the command is still marked
experimental upstream.

- Use an AI assistant or planning agent to:
  - Outline tasks.
  - Generate scaffolding code or documentation.
  - Suggest migration strategies.
  - Track dependencies and risks.
- Store plans in the branch directory (worktrees/...) for traceability.

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
- Drop temporary databases if used.
- Archive AI planning notes if valuable for future reference.


## `scratch/` directory

Working notes. Nothing here is authoritative, current, or reviewed.
Files change frequently and may contradict the code.

- inbox/  — unsorted; triage into active/ or delete
- active/ — being worked on now
- parked/ — paused, still relevant
- archive/— done or abandoned; kept for the reasoning, not the answer

Anything that stabilizes moves to docs/ or becomes an ADR.
