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
git wt add [branch] [options]     # add one worktree to an existing layout
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

#### `git wt add [branch] [options]`

Add a single worktree to an existing layout. Run from anywhere inside the
layout — the container root **or** another worktree.

Why not just `git worktree add`? Because the built-in resolves a relative path
against your **current directory**, so from inside `main/` it would nest the new
worktree at `main/feature/x` instead of as a sibling. `git wt add` always anchors
to the container and names the folder exactly after the branch.

- **Anchored placement.** Creates the worktree at `<container>/<branch>` (verbatim,
  nested for slashed names), regardless of where you run it.
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

## `gj` — fuzzy-jump to local git repos

Pick a git repository found under the current directory with [`fzf`](https://github.com/junegunn/fzf)
and drop your shell into it — optionally running a command once you're there.

```bash
gj                  # fzf-pick a repo, cd into it
gj lazygit          # pick a repo, cd into it, then run `lazygit`
gj git status -sb   # any command + args after the pick
```

It finds every directory containing a `.git` (normal repos, bare
`git-wt` containers, and linked worktrees), skipping heavy dirs like
`node_modules/`.

### Install

`gj` ships as two pieces — a discovery core and a shell function — because a
child process can't change its parent shell's directory, so the `cd` has to run
in your shell:

1. Put `gj-find` on your `PATH`:
   ```bash
   ln -s "$(pwd)/gj-find" ~/.local/bin/gj-find
   ```
2. Source the function from your shell rc (`~/.bashrc` / `~/.zshrc`):
   ```bash
   source /path/to/gj.sh
   ```

`fzf` is recommended; without it, `gj` falls back to a numbered menu.

### Configuration

- `GJ_ROOTS` — colon-separated search roots (default: the current directory),
  e.g. `export GJ_ROOTS="$HOME/src:$HOME/work"`.
- `GJ_MAX_DEPTH` — how deep to search (default: `8`).

## Tests

A zero-dependency test suite (just bash + git) lives in `tests/`:

```bash
./tests/run.sh            # run everything
./tests/run.sh migrate    # only test files matching *migrate*
```

Each test runs in its own throwaway temp dir with an isolated git config, so it
never touches your machine or the network. A test is any `test_*` function in a
`tests/test_*.sh` file; add new ones there. Output is shown only for failures,
and the runner exits non-zero if anything fails (CI-friendly).
