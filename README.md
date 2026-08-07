# Git Worktree Development Workflow with AI Integration

Comprehensive Workflow Guide

## 1. Create a Worktree

- Run: `scripts/create-worktree <app|api> <scope/branch-name>`
- Purpose: Isolate development in a dedicated directory under `worktrees/<app|api>/<scope-branch-name>`.
- Benefit: Keeps the main repo clean while allowing parallel feature or bugfix development.

## 2. Prepare the Database

- Dump the remote development database.
- Load it into your local database for consistency.
- Optionally:
  - Create a temporary branch-specific database when schema migrations are required.
  - This avoids breaking other branches and keeps migrations isolated.

## 3. Plan Development with AI/Agent

- Use an AI assistant or planning agent to:
  - Outline tasks.
  - Generate scaffolding code or documentation.
  - Suggest migration strategies.
  - Track dependencies and risks.
- Store plans in the branch directory (worktrees/...) for traceability.

## 4. Develop in the Worktree

- Navigate to: `worktrees/<app|api>/<scope-branch-name>`
- Implement changes, run tests, and validate against the local/temporary database.
- Keep commits atomic and descriptive for easier review.

## 5. Commit Changes

- Follow conventional commit messages (e.g., feat:, fix:, chore:).
- Ensure commits are scoped to the branch purpose.
- Run pre-commit hooks or linting checks if configured.

## 6. Create a Pull Request (PR)

- Push the branch to remote.
- Open a PR with:
  - Clear description of changes.
  - Migration notes if applicable.
  - Links to AI-generated plans or docs.
- Request review from peers or automated agents.

## 7. Retire the Worktree

After PR merge or branch closure:
- Run cleanup script to remove the worktree.
- Drop temporary databases if used.
- Archive AI planning notes if valuable for future reference.
