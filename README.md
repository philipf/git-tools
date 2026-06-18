# git-tools

A small collection of git helpers and shell scripts for working with repositories and worktrees.

## Install

Run the installer once per machine. It symlinks the executables (`wtx-tool`,
`gj-pick`, `wtc`) and the shell-init helper into `~/.local/bin` (override with
`BINDIR=…`), using absolute paths so they keep working wherever this repo lives:

```sh
./symlink-init.sh
```

Then source the shell wrappers (`wtx`, `gj`, `gjj`) from your `~/.zshrc` /
`~/.bashrc` — point at the **symlink**, not the repo, so it's machine-independent:

```sh
[ -f ~/.local/bin/shell-init.sh ] && source ~/.local/bin/shell-init.sh
```

(Ensure `~/.local/bin` is on your `PATH`.)

## Contents

### [wtx/](wtx/README.md) — bare-repo + worktree layout tool

| Command | What it does |
|---------|-------------|
| `wtx` / `wtx-tool` | Sets up and manages a **bare-repo + worktree** layout — one container folder holding the bare object store and one sibling folder per branch. Supports `init`, `migrate`, and `add`. |

### [gj/](gj/README.md) — Standalone shell tools

Standalone tools that live on your `PATH`.

| Script | What it does |
|--------|-------------|
| `gj` / `gj-pick` | Fuzzy-jump to any git repo or worktree under your home directory (or the current directory with `--cwd`). Uses `fzf` to pick and then `cd`s into it. |

### [wtc/](wtc/README.md) — Work Tree Claude

| Command | What it does |
|---------|-------------|
| `wtc` | Opens a new tmux window named after a branch with a worktrunk worktree set up two ways side-by-side: Claude Code (pane 1, focused) and lazygit (pane 2). Standalone executable (no shell wrapper). |

### [shell-init.sh](shell-init.sh) — shell wrappers

The `cd`-into-place wrappers that must run in your shell (a child process can't
change your shell's directory): `wtx` (for `wtx-tool`), `gj`, and `gjj`. Installed
via the symlink + source line in [Install](#install) above.
