# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this repository is

The source of a workspace scaffold, not the workspace itself. Users copy
`template/` into an empty folder with gitpick (command in `README.md`).
Everything that ships lives under `template/`; the repo root holds only the
tour (`README.md`), the test, and editor config. The product is bash; there
is no package.json.

Three docs, three audiences, plus a stub:

- **`README.md`** (root): the tour for someone deciding to adopt it.
- **`template/references/workspace.md`**: the shipped reference for every
  command, option, exit code and hook. Change it whenever a script's
  behaviour changes.
- **`template/CLAUDE.md`**: shipped placement rules for agents working *inside*
  a workspace. It does not apply to this repository.

`template/README.md` is a short stub the user rewrites to describe their own
workspace; it only points to the reference. Keep reference content out of it.

## Commands

```bash
bash test/smoke.sh             # full end-to-end suite, TAP output
bash test/smoke.sh --keep      # keep the temp workspace for inspection
bash test/smoke.sh --verbose   # set -x
find template/scripts -type f -exec shellcheck -x -P SCRIPTDIR {} +
```

- **No single-test mode.** Checks run in order against one shared workspace,
  each building on the state the previous ones left. `--filter <s>` still
  runs them all but prints only checks whose description contains `<s>`,
  numbered from 1. Failures always print, and a filter that matches
  nothing exits 1.
- **Shellcheck is optional in the suite**: without it the check reports
  `ok N - shellcheck is clean # SKIP shellcheck not installed` and the
  summary counts the skip, so an unlinted run is visible.
- The suite needs no network: it builds `file://` origins under `mktemp -d`,
  isolates `HOME` and git config, and sets `WORKFLOW_NO_GH=1` and
  `WORKFLOW_YES=1`.

## Script architecture

`template/scripts/` holds ten commands (`repo-add`, `task-*`, `branch-*`,
`sync-repos`) over a shared library in `template/scripts/lib/`:

- **`workspace.sh`**: all domain logic as `ws_*` helpers (paths, repo lookup,
  env-branch detection, dirty and unpushed checks, worktree records, landed
  detection, hooks). Commands are thin: parse options, validate everything,
  then act.
- **`log.sh`** and **`colors.sh`**: stderr logging, `die CODE MSG`,
  confirmation prompts. Source them at top level only: `colors.sh` reads
  `"$@"` at source time for `--color`/`--no-color`.

Each command starts with the same symlink-resolving `SCRIPT_DIR` preamble and
sources `lib/workspace.sh`. The workspace root comes from the library's own
location, not the current directory (override: `WORKSPACE_ROOT`).

Contracts every command keeps (full table in
`template/references/workspace.md`, "Conventions"):

- **stdout is payload, stderr is logging**, so
  `cd "$(scripts/task-create feat/login app)"` works.
- **Shared exit codes** 0–7: 2 usage, 3 not found, 4 conflicting state, 5
  hook failed, 6 declined, 7 external tool failed.
- **Idempotent and resumable**: re-running a half-finished command picks up
  where it stopped; validate all repositories before creating anything.

## Portability constraints

These were each fixed after a real bug; keep them.

- **bash 3.2 and git 2.23**: macOS's stock bash. No associative arrays,
  `mapfile`, `${var,,}`, or GNU-only flags such as `readlink -f` (use
  `ws_realpath`).
- **awk reads all its input** instead of exiting at the first match: an early
  exit can SIGPIPE the writer, and `pipefail` then hides the match.
- **`gh` is optional.** Every PR-state lookup has a no-GitHub path, forced by
  `WORKFLOW_NO_GH=1`.

## Domain vocabulary

Use the glossary in `README.md` exactly: task, task folder name, slug, scope,
env branch, branch checkout, landed, retire, plan link, shared files,
lifecycle hook. Env branches are never tasks: `task-create` refuses them and
points to `branch-add`.

## Commits

Conventional commits with a scope, for example `feat(scripts): …`,
`fix(scripts): …`, `docs: …`; `!` marks a breaking change.
