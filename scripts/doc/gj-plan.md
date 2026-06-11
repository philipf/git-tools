# `gj` — Implementation Plan

Implements the spec in [PRD.md](./PRD.md). Style follows `ext-commands/git-wt`:
`#!/usr/bin/env bash`, `set -euo pipefail`, tty-gated colors, small focused
helpers.

## Deliverables

1. `scripts/gj-pick` — the bash worker (executable).
2. README section documenting install (PATH + `gj` shell function).

No tests for v1 (per PRD).

## File: `scripts/gj-pick`

### Header & options

- Shebang `#!/usr/bin/env bash`, `set -euo pipefail`.
- Parse args:
  - `--cwd` → set `root="$PWD"` (default `root="$HOME"`).
  - `-h` / `--help` → usage, exit 0.
  - Any remaining non-flag tokens → accumulate into `query` (joined with spaces),
    passed to `fzf --query`.
  - Unknown `-*` → error to stderr, exit 2.

### Discovery (gather candidate `.git` paths)

Use `fd` to locate every `.git` entry (file or dir) under `$root`, with a custom
ignore file that prunes hidden directories (except `.git`) and `node_modules`:

```bash
fd --hidden --absolute-path --print0 \
   --type f --type d \
   --glob '.git' \
   --ignore-file <(printf '%s\n' '.*' '!.git' 'node_modules') \
   "$root"
```

The ignore file:

```
.*            # ignore (and don't descend into) anything starting with '.'
!.git         # …except .git, which we still want to match
node_modules  # the one common non-hidden offender
```

Notes:
- **`fd` is chosen for speed** — its parallel walk (the `ignore` crate) is
  faster than `find` on a large `$HOME`.
- The `ignore` crate **prunes** an excluded directory rather than merely
  filtering its results, so hidden subtrees (`~/.config`, `~/.local/share`,
  `~/.cache`, …) are never walked — both quiet *and* fast. Verified: a sentinel
  file planted inside an excluded hidden dir is not found.
- `--hidden` is required so `.git` (a hidden entry) is considered at all; the
  `.*` rule then prunes *other* hidden dirs and `!.git` keeps `.git`.
- `--glob '.git'` matches both worktree `.git` files and repo `.git` dirs;
  `--print0` is NUL-delimited (safe for odd paths).
- Process substitution `<(…)` supplies the ignore file inline — no temp file to
  manage.
- `--absolute-path` so classification and `cd` work regardless of `$PWD`.
- Bare containers are **not** excluded by the ignore rules (their `.git` is
  matched, then classified out), so worktrees nested beneath them stay reachable.
- `fd` does not follow symlinks by default — avoids traversal loops.

A denylist of hidden dirs is a losing battle; the single `.*`/`!.git` rule
replaces it.

### Classification → emit working-tree paths

For each `.git` path `g` (with `d = dirname(g)` = the candidate working tree):

```
if [[ -f "$g" ]]; then
    # worktree (or, in principle, submodule — not filtered)
    emit "$d"
elif [[ -d "$g" ]]; then
    bare=$(git config --file "$g/config" --get core.bare 2>/dev/null || echo false)
    if [[ "$bare" != "true" ]]; then
        emit "$d"     # normal repo
    fi
    # bare == true → container, skip (do not emit)
fi
```

- `emit` collapses a leading `$HOME/` to `~/` for display (a plain string
  substitution; only the leading occurrence). Paths outside `$HOME` are emitted
  absolute.
- One `git config --file` spawn per `.git` **directory** only (worktree files
  need no git call). Acceptable cost.

Collect emitted lines into the candidate list (newline-separated). Preserve
`fd`'s emit order — **no sort**.

### Picker

Pipe candidates into `fzf` with flags that implement the edge-case behavior
directly:

```bash
selection=$(printf '%s\n' "${candidates[@]}" \
    | fzf --select-1 --exit-0 --query="$query" --prompt='gj> ')
status=$?
```

- `--select-1` → auto-select when exactly one match (the single-candidate
  auto-jump and single-query-match auto-jump both fall out of this).
- `--exit-0` → exit immediately (status 1) when there are zero matches.
- `--query` → pre-fill from trailing args (empty string = no pre-filter).
- `fzf` draws its UI on `/dev/tty` automatically when stdin is a pipe, so only the
  selected line reaches `stdout`.

### Exit-status handling

```
status 0   → a line was selected:
               expand leading ~/ back to $HOME/, print absolute path to stdout, exit 0
status 1   → no match (empty candidate set or query matched nothing):
               print "no git repos found" to stderr, exit 1
status 130 → ESC / interrupt:
               print nothing, exit 0 (shell stays put)
other      → propagate as a non-zero error
```

The `~/`→`$HOME/` expansion mirrors the display collapse so the printed path is
always absolute and `cd`-able. (If the candidate was emitted absolute because it
lay outside `$HOME`, there is no leading `~/` to expand — pass through unchanged.)

### Usage text

`gj-pick [--cwd] [query]` with a one-line description of each, plus the install
hint (PATH + `gj` function). Mirror `git-wt`'s `usage()` formatting.

## Install / wiring

1. Make executable: `chmod +x scripts/gj-pick`.
2. Put on `PATH` (e.g. symlink):
   ```bash
   ln -s "$(pwd)/scripts/gj-pick" ~/.local/bin/gj-pick
   ```
3. Add the `gj` function to the (chezmoi-managed) shell rc:
   ```sh
   gj() { local d; d=$(gj-pick "$@") || return; [ -n "$d" ] && cd "$d"; }
   ```
   - `d=$(gj-pick "$@") || return` → on worker non-zero exit (no match / error),
     the function returns without `cd`.
   - `[ -n "$d" ]` guard → on ESC (worker exits 0 with empty stdout), no `cd`.
   - POSIX-compatible body → works in both `zsh` and `bash`.

## README updates

Add a `gj` / `gj-pick` section to `scripts/` (or the repo README) covering:
- what it does (jump to repos & worktrees),
- dependencies (`fd`, `fzf`, `git`),
- the PATH install and the `gj` function snippet,
- usage table (`gj`, `gj --cwd`, `gj <query>`).

## Manual verification checklist

- `gj` from a fresh shell lists repos under `~`; picking one changes directory.
- A `git-wt` layout shows each worktree but **not** the bare container.
- `gj --cwd` from inside a tree limits results to that subtree.
- `gj <unique-substring>` auto-jumps (single match, no picker).
- A scope with exactly one repo auto-jumps.
- A scope with no repos prints `no git repos found` and leaves you put.
- ESC leaves you put, silently.
- `gj-pick` (without the function) prints a path to stdout and is pipeable.

## Risks / notes

- The hidden-dir prune means a repo deliberately kept *inside* a hidden directory
  (e.g. a dotfiles checkout at `~/.dotfiles`) will not be listed. Acceptable
  trade-off: those are rare and the noise reduction is large. Revisit if needed.
- `fd` ignores `.gitignore`d content by default, *and* our custom ignore prunes
  hidden dirs + `node_modules`; a non-hidden vendored `.git` outside those could
  still appear, but none observed in practice. Add a pattern to the ignore file
  if one shows up.
- Requires an `fd` whose `--ignore-file` accepts our patterns (stable across
  recent `fd`; flags used: `--hidden`, `--absolute-path`, `--print0`, `--type`,
  `--glob`, `--ignore-file`).
- Bareness check relies on `core.bare` being present/`true` in a bare repo's
  config (true for `git-wt`-created bare stores and standard bare repos).
