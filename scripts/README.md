# scripts

Standalone helper tools.

## `gj-pick` / `gj` — fuzzy-jump to a git repo or worktree

Fuzzy-pick a git working tree with `fzf` and `cd` into it. Lists **normal repos
and `git-wt` worktrees**; bare containers are skipped (you can't do git work
there), so every entry is somewhere you can actually land.

```
gj            # pick from repos under ~
gj --cwd      # pick from repos under the current directory
gj api        # pre-filter the picker with "api"
gj --cwd api  # combine scope + query
```

- **Exactly one match** → jumps immediately, no picker.
- **No matches** → `no git repos found` on stderr, you stay put.
- **ESC** → silent, you stay put.

### Dependencies

`fd`, `fzf`, `git`.

The scan (via `fd`) never descends into hidden directories (`~/.config`,
`~/.local/share`, `~/.cache`, …) except `.git` itself, plus `node_modules` — so
foreign repos in those don't clutter the picker, and the prune keeps it fast. A
repo deliberately kept inside a hidden dir (e.g. `~/.dotfiles`) won't be listed.

### Install

The worker (`gj-pick`) prints the chosen path; a small shell function does the
`cd` (a child process can't change its parent shell's directory).

1. Put `gj-pick` on your `PATH` (e.g. symlink it):

   ```bash
   ln -s "$(pwd)/gj-pick" ~/.local/bin/gj-pick
   ```

2. Add the `gj` function to your shell rc (`~/.zshrc` / `~/.bashrc` — works in
   both):

   ```sh
   gj() { local d; d=$(gj-pick "$@") || return; [ -n "$d" ] && cd "$d"; }
   ```

`gj-pick` on its own just prints a path to stdout (pipeable / scriptable);
`gj` is the interactive jump.

### Design docs

- [doc/PRD.md](doc/PRD.md) — product requirements.
- [doc/gj-plan.md](doc/gj-plan.md) — implementation plan.
