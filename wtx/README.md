# wtx

A bare-repo + worktree layout tool.

## `wtx` — bare-repo + worktree layout

Sets up and migrates repos to a **bare-repo + worktree** layout: one container
folder holds the bare object store (`.git/`) plus one sibling folder per
checked-out branch.

```
myrepo/
├── .git/        ← bare object store
├── main/        ← worktree for branch `main`
└── feature-x/   ← worktree for branch `feature/x` (folder flattened: `/` → `-`)
```

This is handy for running several agents/editors in parallel, each in its own
clean worktree sibling. A slashed branch like `feature/x` keeps its slash as a
ref but lives in a flat folder `feature-x/`, so you never have to navigate
through empty intermediate directories.

### Install

Run [`symlink-init.sh`](../symlink-init.sh) at the repo root once per machine —
it symlinks `wtx-tool` onto your `PATH` along with the other tools:

```bash
../symlink-init.sh
wtx-tool help
```

> Standalone command `wtx` (not a `git` subcommand) — the name `wt` is taken by
> worktrunk, and `git worktree` is already a built-in.

### `wtx` — auto-`cd` into the new worktree

`wtx add`/`init`/`migrate` create a worktree and then tell you to `cd` into
it — because a subprocess can't change its parent shell's directory. The `wtx`
shell function (in [`shell-init.sh`](../shell-init.sh) at the repo root, alongside
`gj`/`gjj`) wraps `wtx-tool` and lands you there automatically. After running the
installer above, source it from your shell rc (`~/.zshrc` / `~/.bashrc` — works in
both) via the symlink, so it's machine-independent:

```sh
[ -f ~/.local/bin/shell-init.sh ] && source ~/.local/bin/shell-init.sh
```

Then:

```bash
wtx add feature/x   # creates the worktree, then drops you inside it
wtx init            # → cd into the new worktree
wtx migrate         # → cd into the current branch's worktree
```

How it works: when `WTX_CD_FILE` is set, `wtx-tool` writes the absolute path of
the worktree to that file on success; the function reads it back and `cd`s. Plain
`wtx-tool …` (the var unset) behaves exactly as before and just prints the `cd`
hint. The jump is skipped for no-ops — a `--dry-run`, or an `add`/`migrate` that
finds the worktree already there leaves you put.

### Usage

```bash
wtx init [branch]              # brand-new repo (no .git, no remote)
wtx migrate [--dry-run] [-y]   # convert an existing repo in place
wtx add [branch] [options]     # add one worktree to an existing layout
```

#### `wtx init [branch]`

Run in the directory you want as the container.

- Aborts if a `.git` already exists (not a brand-new repo).
- Branch name: the argument, else `init.defaultBranch`, else `main`.
- Creates `.git/` (bare) and a `<branch>/` worktree with an **unborn** branch
  (no synthetic commit — same feel as a fresh `git init`).
- If the directory already had files, they're moved into `<branch>/`, untracked
  and ready for the first commit.

#### `wtx migrate [--dry-run] [-y]`

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

#### `wtx add [branch] [options]`

Add a single worktree to an existing layout. Run from anywhere inside the
layout — the container root **or** another worktree.

Why not just `git worktree add`? Because the built-in resolves a relative path
against your **current directory**, so from inside `main/` it would nest the new
worktree at `main/feature-x` instead of as a sibling. `wtx add` always anchors
to the container and names the folder after the branch with `/` flattened to `-`.

- **Anchored, flat placement.** Creates the worktree at
  `<container>/<branch-with-slashes-as-dashes>` (so `feature/x` → `feature-x/`),
  regardless of where you run it. The branch ref keeps its slashes.
- **Offline branch resolution.** Existing local branch → checked out; otherwise a
  matching remote-tracking branch (e.g. `origin/<branch>`) → a local tracking
  branch (no fetch); otherwise a **new** branch from `--from` (default `HEAD`).
- **Runnable worktree.** Copies git-ignored files (`.env`, …) from a source
  worktree (the one you're in, else the default branch's) so the new worktree
  works immediately. Heavy/regenerable dirs (`node_modules/`, `.venv/`, …) are
  **skipped** with a reinstall hint; `--copy-all` copies them too (copy-on-write
  where the filesystem supports it).
- **No branch given?** Pick one interactively from the branches that don't have a
  worktree yet.
- **Layout-only.** Aborts (pointing at `migrate`) if the repo isn't a bare-repo
  layout. Never contacts or mutates the remote.

Flags:

- `--from <ref>` — base ref for a brand-new branch (default `HEAD`).
- `--copy-all` — also copy the skipped heavy dirs.
- `--no-copy-ignored` — copy no ignored files.
- `-n`, `--dry-run` — print the plan and exit; change nothing.

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
