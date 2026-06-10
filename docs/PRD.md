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

In scope: three subcommands — `init` (brand-new repo), `migrate` (existing
repo), and `add` (create one more worktree in an existing layout). Out of scope
(for now): `list`, `remove`, and `switch` subcommands, and any remote-mutating
behaviour.

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
  `add`, and `help`.
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

### `add`

> IDs use the `D` prefix (*a**D**d*) because `A` already denotes Assumptions.

- **D1 (Ubiquitous).** `add` shall create a single new worktree in the layout,
  placing it as a sibling of `.git/` in the container, with the folder named
  exactly after its branch (verbatim, nested for slashed names) — the same
  invariant as G5/G6.
- **D2 (Ubiquitous).** `add` shall resolve the container as the parent of the git
  common directory (`git rev-parse --git-common-dir`), so it places the worktree
  correctly regardless of the current working directory — including when run from
  inside an existing (possibly nested) worktree.
- **D3 (Unwanted behaviour).** If the current directory is not inside a git
  repository, then `add` shall abort with an error.
- **D4 (Event-driven).** When `add` is given a branch name that exists as a local
  branch, the tool shall check that branch out into the new worktree.
- **D5 (Event-driven).** When the branch does not exist locally but a matching
  remote-tracking branch exists (for example `origin/<branch>`), `add` shall
  create a local branch tracking it, using only already-fetched refs (no
  network).
- **D6 (Event-driven).** When the branch exists neither locally nor on a remote,
  `add` shall create a new branch from the base ref given by `--from <ref>`,
  defaulting to `HEAD`.
- **D7 (Unwanted behaviour).** If a worktree for the branch already exists, then
  `add` shall print its path and exit successfully without making changes.
- **D8 (Unwanted behaviour).** If the target folder already exists but is not the
  worktree for that branch, then `add` shall abort without clobbering it.
- **D9 (State-driven).** While git-ignored env files matching the copy set
  (default `.env*` at the worktree root) exist in the source worktree, `add`
  shall copy them into the new worktree so it is immediately runnable. The source
  is the worktree the current directory is in, or — when run from outside any
  worktree — the default branch's worktree.
- **D10 (Optional).** Where `--no-copy-ignored` is given, `add` shall copy no
  ignored files; where `--copy-ignored <glob>` is given (repeatable), `add` shall
  extend the set of patterns it copies.
- **D11 (Ubiquitous).** `add` shall only copy files that are genuinely
  git-ignored in the source and match the copy set, and shall never overwrite an
  existing file in the new worktree.
- **D12 (Event-driven).** When `--dry-run`/`-n` is given, `add` shall print the
  plan (folder to create, how the branch resolves, files to copy) and exit
  without making any change.
- **D13 (Ubiquitous).** `add` shall not contact or mutate any remote (offline,
  per N1) and shall be non-destructive (per N2): it only ever adds a worktree and
  copies ignored files, so it needs no confirmation prompt.
- **D14 (Event-driven).** When `add` finishes, the tool shall print the resulting
  layout and the next step (for example `cd <container>/<branch>`).

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
- Creating worktrees for branches that exist only on the remote (during
  `migrate`).
- Fetching from the remote during `add` — it resolves only already-fetched
  remote-tracking branches; the user fetches first if needed.
- `list`, `remove`, and `switch` subcommands.
