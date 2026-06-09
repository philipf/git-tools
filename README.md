# git-scripts

Small git helpers.

## `git-wt` — bare-repo + worktree layout

Sets up and migrates repos to a **bare-repo + worktree** layout: one container
folder holds the bare object store (`.git/`) plus one sibling folder per
checked-out branch.

```
myrepo/
├── .git/        ← bare object store
├── main/        ← worktree for branch `main`
└── feature/x/   ← worktree for branch `feature/x`
```

This is handy for running several agents/editors in parallel, each in its own
clean worktree sibling.

### Install

Symlink it onto your `PATH` as `git-wt` (no extension) so git exposes it as the
`git wt` subcommand:

```bash
ln -s "$(pwd)/git-wt" ~/.local/bin/git-wt
```

Then:

```bash
git wt help
```

> Named `git-wt` (not `git-worktree`) on purpose — `git worktree` is already a
> built-in git command.

### Usage

```bash
git wt init [branch]              # brand-new repo (no .git, no remote)
git wt migrate [--dry-run] [-y]   # convert an existing repo in place
```

#### `git wt init [branch]`

Run in the directory you want as the container.

- Aborts if a `.git` already exists (not a brand-new repo).
- Branch name: the argument, else `init.defaultBranch`, else `main`.
- Creates `.git/` (bare) and a `<branch>/` worktree with an **unborn** branch
  (no synthetic commit — same feel as a fresh `git init`).
- If the directory already had files, they're moved into `<branch>/`, untracked
  and ready for the first commit.

#### `git wt migrate [--dry-run] [-y]`

Run from the root of an existing repo (local-only or with a remote).

- Reuses the existing `.git` (flips it to bare) — **lossless**: keeps all local
  branches, tags, stashes, and reflog. No network.
- **Requires a clean working tree** (aborts and lists offending files otherwise).
- Creates a worktree folder for **every local branch**.
- Removes the now-redundant committed files from the container root (they're
  recreated inside the worktrees).
- Moves git-ignored files (`.env`, `node_modules/`, …) into the current branch's
  worktree so secrets and deps follow the code.
- **Touches nothing about the remote.** A read-only sanity check warns (without
  changing anything) if the fetch refspec or `origin/HEAD` looks broken.
- **Idempotent / resumable**: if interrupted, re-running creates only the missing
  worktrees.

Flags:

- `--dry-run` — print the plan and exit; change nothing.
- `-y`, `--yes` — skip the confirmation prompt.

### Tests

A zero-dependency test suite (just bash + git) lives in `tests/`:

```bash
./tests/run.sh            # run everything
./tests/run.sh migrate    # only test files matching *migrate*
```

Each test runs in its own throwaway temp dir with an isolated git config, so it
never touches your machine or the network. A test is any `test_*` function in a
`tests/test_*.sh` file; add new ones there. Output is shown only for failures,
and the runner exits non-zero if anything fails (CI-friendly).
