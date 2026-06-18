# wtc

"Work Tree Claude" — spin up a [worktrunk](https://worktrunk.dev) worktree with
Claude Code, in its own tmux window, in one command.

## `wtc` — worktree + Claude in a named tmux window

```sh
wtc <branch> [-- <task>...]
wtc feat/login -- 'Fix GH #322'
```

Opens a new tmux window in the current session, **named after the branch**, and
runs `wt switch --create <branch> -x claude [-- <task>]` inside it. Handy for
firing off parallel agents — each branch gets its own clearly-labelled window.

The new window is a real interactive shell, so it:

- loads your rc (`PATH`, `mise`, the `wt` shell integration), and
- stays open after Claude exits, leaving you in the worktree.

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
- [`wt`](https://worktrunk.dev) and `claude` available in your interactive shell.
