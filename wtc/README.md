# wtc

"Work Tree Claude" — spin up a [worktrunk](https://worktrunk.dev) worktree with
Claude Code, in its own tmux window, in one command.

## `wtc` — worktree + Claude + lazygit in a named tmux window

```sh
wtc <branch> [-- <task>...]
wtc feat/login -- 'Fix GH #322'
```

Opens a new tmux window in the current session, **named after the branch**, and
sets up a worktrunk worktree two ways, side by side:

```
┌───────────┬───────────┐
│  claude   │  lazygit  │   pane 1: wt switch <branch> -x claude [-- task]
│ ◀ focus   │           │   pane 2: wt switch <branch> -x lazygit
└───────────┴───────────┘   focus returns to pane 1
```

Handy for firing off parallel agents — each branch gets its own clearly-labelled
window with Claude Code and a git UI on the same worktree.

Both panes are real interactive shells, so they load your rc (`PATH`, `mise`, the
`wt` shell integration) and stay open after the tool exits, leaving you in the
worktree.

### How the worktree is set up

The worktree is **created once up front** (`wt switch --create <branch> --no-cd`,
which is a no-op if it already exists), then each pane runs
`wt switch <branch> -x <tool>`. This means:

- **worktrunk owns the `cd`** into the worktree — `wtc` never reconstructs the
  worktree path itself (its on-disk layout is `wt`'s business), and it doesn't
  rely on tmux pane-cwd inheritance, which would race the async pane-1 startup.
- pane 2 can't race pane 1's creation, because the worktree already exists.

The `<branch> [-- <task>...]` shape mirrors worktrunk's own
`wt switch <branch> [-- <args>...]`, so you supply the `--` separator just as you
would for `wt`.

### Install

Run [`symlink-init.sh`](../symlink-init.sh) at the repo root once per machine —
it symlinks `wtc` onto your `PATH` along with the other tools:

```sh
../symlink-init.sh
wtc feat/test -- 'say hello'
```

> Standalone command on your `PATH` — **not** a shell function. Unlike the
> `cd`-into-place wrappers in [`shell-init.sh`](../shell-init.sh) (which must run
> in your shell because a child can't change its parent's directory), every side
> effect here targets the tmux server (`new-window`, `send-keys`), so a plain
> binary works fine. Nothing to source from your rc.

### Requirements

- Running inside `tmux` (`wtc` refuses otherwise).
- [`wt`](https://worktrunk.dev), `claude`, and `lazygit` available in your
  interactive shell.
