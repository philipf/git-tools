# `gj` — Product Requirements

## Summary

`gj` is a command-line tool to **fuzzy-pick a git working tree and `cd` into it**.
It scans for git repositories (and `git-wt` worktrees) under a root directory,
presents them in an `fzf` picker, and changes the current shell's directory to
the chosen one.

It lands on **actual working trees** — normal repos and worktrees — and never on
bare containers, so every entry is somewhere you can actually do git work.

## Motivation

Repos on this machine use the `git-wt` **bare-repo + worktree layout**: a
container holds a bare `.git/` object store plus one sibling folder per
checked-out branch:

```
myrepo/
├── .git/        ← bare object store (you don't work here)
├── main/        ← worktree
└── feature/x/   ← worktree
```

`gj` lets you jump quickly between these worktrees as well as ordinary repos,
without remembering or typing paths.

## Users / Context

Single-user developer tool, invoked interactively from a `zsh` (and `bash`)
shell. Part of the `git-tools` repository alongside `git-wt`.

## Functional Requirements

### Invocation

| Invocation              | Behavior                                            |
| ----------------------- | --------------------------------------------------- |
| `gj`                    | Scan `~` (home directory).                          |
| `gj --cwd`              | Scan `$PWD` (current working directory) instead.    |
| `gj [--cwd] <text>`     | Trailing text pre-fills the `fzf` query.            |

- The argument surface is intentionally minimal: `--cwd`, plus optional trailing
  query text. No arbitrary-path scoping flag.
- Query text combines with either scope (e.g. `gj --cwd api`).

### Jump targets (classification)

The tool must list **working trees only**. Under the chosen root, for every
`.git` encountered:

- `.git` is a **file** → it is a worktree → **list its parent**.
- `.git` is a **directory** and is **not bare** (`core.bare != true`) → it is a
  normal repo → **list its parent**.
- `.git` is a **directory** and **is bare** (`core.bare == true`) → it is a
  container → **do not list it**, but the scan must still descend *through* it to
  discover the worktrees nested beneath it.
- No special handling for submodules (none are in use). Any `.git` file is
  treated as a worktree.

The scan **never descends into hidden directories** (those whose name starts with
`.`), except `.git` itself. This avoids the foreign-repo noise that lives in
`~/.config`, `~/.local/share`, `~/.cache`, etc. without an ever-growing denylist.
`node_modules` (the one common *non-hidden* offender) is pruned too. `.git`
directories are matched but not descended into.

### Picker behavior

- Entries are displayed as **`~`-collapsed full paths** (e.g.
  `~/work/myrepo/feature/x`). Full paths disambiguate worktrees whose basenames
  (`main`, `feature/x`) repeat across repos, and every path segment is
  fuzzy-searchable.
- List order is **`fd`'s native emit order** — no sorting. (`fzf` preserves input
  order only on an empty query and ranks by match score once you type, so the
  order only affects the top highlight on an empty query.)
- **No preview pane.**
- On selection, the tool resolves the chosen `~`-collapsed path back to its
  absolute form and the shell `cd`s into it.

### Edge cases

- **Exactly one match** → auto-jump to it without opening the picker.
- **Zero matches** → print `no git repos found` to **stderr**, exit non-zero, no
  `cd`.
- **Cancel (ESC)** → silent, no message, no `cd`, the shell stays put.

## Non-Functional Requirements

- **Dependencies:** `fd`, `fzf`, `git` are hard dependencies. `fd` is used for
  the scan (its parallel walk is faster than `find` on a large `$HOME`).
- **Performance:** live scan on every invocation (no cache for v1). `fd`'s
  parallel walk, plus a custom ignore that *prunes* all hidden subtrees and
  `node_modules` (the `ignore` crate skips excluded dirs rather than walking
  them), removes the bulk of `$HOME` and keeps the scan fast.
- **Shell support:** the `gj` function must work in both `zsh` and `bash`.
- **Stdout contract:** the worker prints **only** the chosen path to stdout; the
  `fzf` UI uses `/dev/tty`. This keeps the wrapper function's command
  substitution clean.

## Architecture / Packaging

The shell cannot have its working directory changed by a child process, so `gj`
is split into a worker plus a thin shell function:

- **`scripts/gj-pick`** — the bash worker. Put on `PATH` (e.g. symlinked into
  `~/.local/bin`); prints the chosen path to stdout and is usable standalone in
  scripts. (A plain standalone name rather than a `git-` subcommand: the only
  intended entry point is the `gj` function, so the git-dispatch hop adds no
  value.)
- **`gj` shell function** — a small wrapper that lives in the (chezmoi-managed)
  shell rc and does the `cd`:

  ```sh
  gj() { local d; d=$(gj-pick "$@") || return; [ -n "$d" ] && cd "$d"; }
  ```

The function snippet is documented in the README; users add it to their shell
config themselves.

## Out of Scope (v1)

- Caching / frecency / recency-based ordering.
- Preview pane.
- Arbitrary-path scope argument.
- Submodule filtering.
- Automated tests (may be added later).

## Open Questions

None — all design decisions resolved.
