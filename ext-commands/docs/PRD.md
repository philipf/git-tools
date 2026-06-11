# PRD: `git-wt` — bare-repo + worktree layout tool

## Purpose

`git-wt` lets a developer create or convert a git repository into a
**bare-repo + worktree** layout: one container folder holds the bare object
store (`.git/`) plus one sibling folder per branch.

```
myrepo/
├── .git/        ← bare object store
├── main/        ← worktree for branch `main`
└── feature/x/   ← worktree for branch `feature/x`
```

This makes it easy to work on several branches — or run several agents/editors —
side by side, each in its own clean folder.

## Scope

In scope: two subcommands, `init` (brand-new repo) and `migrate` (existing
repo). Out of scope (for now): `add`, `list`, `remove` worktree subcommands, and
any remote-mutating behaviour.

## Requirements (EARS)

EARS = *Easy Approach to Requirements Syntax*. Each requirement uses one of the
standard patterns:

- **Ubiquitous** — "The system shall …" (always true)
- **Event-driven** — "When `<trigger>`, the system shall …"
- **State-driven** — "While `<state>`, the system shall …"
- **Unwanted behaviour** — "If `<condition>`, then the system shall …"
- **Optional** — "Where `<feature>` is present, the system shall …"

### General

- **G1 (Ubiquitous).** The tool shall be a single executable named `git-wt` so it
  can be run as the git subcommand `git wt`.
- **G2 (Ubiquitous).** The tool shall support the subcommands `init`, `migrate`,
  and `help`.
- **G3 (Event-driven).** When the tool is run with no subcommand, or with `help`,
  `-h`, or `--help`, the tool shall print usage and exit successfully.
- **G4 (Unwanted behaviour).** If an unknown subcommand is given, then the tool
  shall print usage and exit with an error.
- **G5 (Ubiquitous).** The tool shall produce the layout with the bare store
  named `.git/` directly (no `.bare` pointer file).
- **G6 (Ubiquitous).** The tool shall name each worktree folder exactly after its
  branch, so a branch like `feature/x` becomes a nested folder `feature/x/`.

### `init`

- **I1 (Ubiquitous).** `init` shall operate on the current directory, treating it
  as the container.
- **I2 (Unwanted behaviour).** If a `.git` file or directory already exists in the
  current directory, then `init` shall abort and tell the user to use `migrate`
  instead.
- **I3 (Event-driven).** When `init` is given a branch name argument, the tool
  shall use that name for the first branch.
- **I4 (Event-driven).** When `init` is given no branch name, the tool shall use
  `init.defaultBranch` from git config, falling back to `main` if it is unset.
- **I5 (Ubiquitous).** `init` shall create a bare repository at `.git/` and add a
  worktree for the first branch as an **unborn** branch, with no synthetic
  initial commit.
- **I6 (State-driven).** While the current directory already contains files (but
  no `.git`), `init` shall move those existing files into the new worktree folder
  so they are untracked and ready for the first commit.
- **I7 (Ubiquitous).** `init` shall not contact or configure any remote.
- **I8 (Event-driven).** When `init` finishes, the tool shall print the resulting
  layout and the next steps.

### `migrate`

- **M1 (Ubiquitous).** `migrate` shall operate in place on the existing repository
  in the current directory, reusing the existing `.git` so that all local
  branches, tags, stashes, and reflog are preserved.
- **M2 (Unwanted behaviour).** If the current directory is not inside a git
  repository, then `migrate` shall abort with an error.
- **M3 (Unwanted behaviour).** If the current directory is not the repository
  root, then `migrate` shall abort and name the root.
- **M4 (Unwanted behaviour).** If the working tree is not clean (any staged,
  unstaged, or untracked files), then `migrate` shall list the offending files
  and abort, asking the user to commit, stash, or clean first.
- **M5 (Event-driven).** When the preconditions pass, `migrate` shall print a plan
  describing every change before making any change.
- **M6 (Event-driven).** When `--dry-run` is given, `migrate` shall print the plan
  and exit without making any change.
- **M7 (Unwanted behaviour).** If `-y`/`--yes` is not given and the run is not a
  dry run, then `migrate` shall ask for confirmation and abort unless the user
  agrees.
- **M8 (Ubiquitous).** `migrate` shall convert the repository to bare and create a
  worktree folder for **every** local branch.
- **M9 (Ubiquitous).** `migrate` shall remove from the container root only files
  that exist verbatim in a commit (because they are recreated inside the
  worktrees).
- **M10 (State-driven).** While git-ignored files (such as `.env` or
  `node_modules/`) exist in the repository, `migrate` shall move them into the
  current branch's worktree; if the repository is on a detached HEAD, it shall use
  the default branch's worktree instead.
- **M10a (Ubiquitous).** `migrate` shall preserve each ignored file's path when
  moving it, so an ignored file nested inside a tracked directory (for example
  `worker/node_modules/`) is placed back at the same relative path inside the
  worktree's recreated tracked directory, rather than displacing or colliding
  with that directory.
- **M11 (Ubiquitous).** `migrate` shall not write any change to remote
  configuration: the fetch refspec, remote-tracking refs, `origin/HEAD`, and
  per-branch upstreams shall remain exactly as they were.
- **M12 (Unwanted behaviour).** If a remote exists and its fetch refspec or
  `origin/HEAD` looks broken, then `migrate` shall print a warning with the fix
  but make no change.
- **M13 (State-driven).** While the repository is already bare (for example after
  an interrupted migrate), `migrate` shall resume: it shall skip the clean-tree
  check, the bare conversion, and committed-file removal, and create only the
  worktrees that are missing.
- **M14 (Event-driven).** When every local branch already has a worktree,
  `migrate` shall report that nothing needs doing and exit successfully.
- **M15 (Event-driven).** When `migrate` finishes, the tool shall print the
  resulting layout and the next steps.

## Non-functional requirements

- **N1 (Ubiquitous).** The tool shall run offline; no subcommand shall require
  network access.
- **N2 (Ubiquitous).** The tool shall be non-destructive: it shall only ever
  delete files that are safely recoverable from a commit.
- **N3 (Ubiquitous).** `migrate` shall be idempotent — running it again after a
  successful or interrupted run shall converge to the same layout without error.
- **N4 (Ubiquitous).** The tool shall stop on the first error
  (`set -euo pipefail`) and report a clear message.
- **N5 (Optional).** Where output is a terminal, the tool shall use colour to
  highlight steps, warnings, and errors; otherwise it shall use plain text.

## Assumptions

- **A1.** git is version 2.42 or newer (for `git worktree add --orphan`).
- **A2.** All worktree folders live on the same filesystem as the container, so
  moves are fast.
- **A3.** The user installs the tool on their `PATH` as `git-wt` (typically via a
  symlink) so that `git wt` resolves to it.

## Out of scope

- Setting up or pushing to a remote during `init`.
- Repairing remote configuration during `migrate` (it only warns).
- Creating worktrees for branches that exist only on the remote.
