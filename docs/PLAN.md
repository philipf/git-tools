# Plan: `git-wt` — bare-repo + worktree layout tool

> Design record for `git-wt`. Decisions below were settled in a Q&A session and
> verified end-to-end against real repos. Kept for future reference.

## Context

The bare-repo + worktree layout puts one container folder holding the bare
object store (`.git/`) plus one sibling folder per checked-out branch. Setting
it up by hand is a fiddly multi-step dance (bare init/clone, refspec fix, fetch,
per-worktree upstream). `git-wt` automates the two entry points:

- **`init`** — stand up the layout in a brand-new repo (no `.git`, no remote).
- **`migrate`** — convert an existing repo (local-only or with a remote) into
  the same clean layout, losslessly and without touching the remote.

A motivating use case is running parallel agents/editors at once, each in its
own clean worktree sibling.

## Resulting layout (target)

```
myrepo/
├── .git/        ← bare object store (named .git directly, no pointer file)
├── main/        ← worktree for branch `main`
└── feature/x/   ← worktree for branch `feature/x` (verbatim, nested ok)
```

## Form & packaging

- **Single bash file** `git-wt` (no extension), `#!/usr/bin/env bash`,
  `set -euo pipefail`.
- Subcommand **dispatcher**: `init`, `migrate`, `help` (room for future
  `add`/`list`/`remove`); shared helper functions at the top.
- Named `git-wt` (not `git-worktree`) so git's `git foo → git-foo` mapping makes
  it invokable as **`git wt …`** without colliding with the built-in
  `git worktree`.
- **Install:** symlink `~/.local/bin/git-wt → repo/git-wt` (that dir is on PATH).

## `git wt init [branch]`

Operates on the current directory (the container).

1. **Abort** if `.git` exists (dir *or* file) — not a brand-new repo.
2. Resolve branch name: positional arg → else `git config init.defaultBranch`
   → else `main`.
3. `git init --bare .git`.
4. `git worktree add --orphan <branch>` — unborn branch, **no synthetic commit**
   (matches a fresh `git init`; requires git ≥ 2.42).
5. If the directory was **non-empty** beforehand (files but no `.git`), move
   those entries into `<branch>/` so they're untracked and ready for the first
   commit. Empty dir → empty worktree.
6. No remote interaction (precondition: no remote).
7. Print resulting tree + next steps.

## `git wt migrate [--dry-run] [-y]`

Operates in-place on the current repo. Strategy: **reuse the existing `.git`**
(flip to bare) — lossless (keeps all local branches, tags, stashes, reflog), no
network, identical path for local-only and remote repos.

1. **Preconditions:**
   - Must be the **root** of a git repo.
   - **Non-bare repo:** abort if the working tree is dirty
     (`git status --porcelain` non-empty) — print offending files. Removal only
     ever touches files that exist verbatim in a commit.
   - **Already bare:** enter *resume mode* (see below) instead of aborting.
2. **Plan + confirm:** print the plan (branches→folders to create, committed
   files to remove, ignored files to move). Prompt `[y/N]`.
   - `--dry-run` → print plan and exit, change nothing.
   - `-y`/`--yes` → skip the prompt.
3. `git config core.bare true`.
4. Remove the now-redundant **committed** files from the container root
   (recreated inside worktrees).
5. For **every local branch**: `git worktree add <branch> <branch>` (verbatim
   folder names; slashed names → nested folders).
6. **Move git-ignored files** (`.env`, `node_modules/`, `dist/`, …) into the
   current branch's worktree (or, if detached HEAD, the default branch's —
   `init.defaultBranch`, else first branch) so secrets/deps follow the code.
7. **Remote: write nothing.** Reusing `.git` keeps the fetch refspec,
   `origin/*` refs, `origin/HEAD`, and per-branch upstreams intact. **Read-only
   sanity check** only: warn (no changes) if the fetch refspec or `origin/HEAD`
   looks broken.
8. Print resulting tree + next steps.

### Resume mode (idempotent migrate)

A migrate that dies mid-loop leaves the repo **already bare** with only some
worktrees created. Re-running must continue, not abort. So when the repo is
already bare, migrate:

- skips the clean-tree check, the `core.bare` flip, and committed-file removal
  (inapplicable — a bare repo has no work tree at the root);
- creates only the **missing** worktrees;
- reports *"Already migrated — nothing to do"* when every local branch already
  has a worktree.

## `git wt add [<branch>] [--from <ref>] [--no-copy-ignored] [--copy-ignored <glob>]... [-n]`

Adds **one** worktree to an existing layout. Additive and non-destructive, so —
unlike `migrate` — it has **no confirm prompt**; `--dry-run`/`-n` still prints
the plan and changes nothing.

### Why a wrapper beats raw `git worktree add`

The built-in resolves a relative `<path>` against the **current shell
directory**, not the container. In this layout that bites hard: from inside
`main/`, `git worktree add feature/x feature/x` creates `main/feature/x/` —
nested under `main`, not a sibling of `.git/` — and you must type the branch
twice and compute the right `../` prefix (worse from already-nested worktrees).
`add` removes all of that and, by default, copies `.env`-style files so the new
worktree actually runs (mirrors `migrate`'s ignored-file handling, M10).

### Steps

1. **Anchor to the container.** `container = dirname(git rev-parse
   --git-common-dir)`. The worktree always lands at `<container>/<branch>`
   regardless of CWD.
2. **Resolve the branch (offline):**
   - local branch exists → `git worktree add <container>/<branch> <branch>`;
   - else remote-tracking `<remote>/<branch>` exists (prefer `origin`) →
     `git worktree add --track -b <branch> <container>/<branch> <remote>/<branch>`;
   - else new branch → `git worktree add -b <branch> <container>/<branch> <base>`,
     where `base = --from` else `HEAD`.
3. **Guards.** If a worktree for the branch already exists → print its path,
   exit 0. If `<container>/<branch>` exists but isn't that worktree → abort
   (don't clobber).
4. **Copy ignored env files** (default on). Source worktree = the one the CWD is
   in, else the default branch's worktree (`default_branch_name`). For each
   pattern in the copy set (default `.env*` at the worktree root; extend with
   repeatable `--copy-ignored <glob>`), copy matching files that are (a)
   git-ignored in the source and (b) absent in the new worktree. Never
   overwrite. `--no-copy-ignored` disables the step entirely.
5. **No network, no remote writes** (N1). Remote-tracking resolution reads only
   already-fetched refs.
6. Print the resulting tree + next step (`cd <container>/<branch>`).

### Key impl notes

- Container / common-dir: `git rev-parse --git-common-dir` → parent. Works from
  the container root (bare) or from any worktree.
- Existing-worktree lookup: `git worktree list --porcelain`, match
  `branch refs/heads/<branch>` or `worktree <container>/<branch>`.
- Remote-tracking existence: `git show-ref --verify --quiet
  refs/remotes/origin/<branch>` (iterate remotes if origin lacks it).
- Ignored check: `git -C <source> check-ignore -q <file>` before copying; the
  default glob stays at the worktree root to avoid surprises.
- **Copy, not symlink:** each worktree's `.env` stays independent, so parallel
  agents can diverge config without clobbering a shared file. A future `--link`
  flag could offer symlinks; out of scope now.
- Reuses existing helpers — `default_branch_name`, `print_tree`, colour, `run`
  (honours `DRY_RUN`), `die` — and slots into the dispatcher beside `init`/
  `migrate`.

## Key implementation notes / edge cases

- Repo root: `git rev-parse --show-toplevel` == `$PWD`.
- Bare/non-bare: `git rev-parse --is-bare-repository`.
- Local branches: `git for-each-ref --format='%(refname:short)' refs/heads`.
- Existing worktrees (idempotency): `git worktree list --porcelain` →
  `worktree ` lines.
- Committed root entries to remove: `git ls-tree --name-only HEAD` (top level).
- Ignored entries to move: `git ls-files --others --ignored --exclude-standard
  --directory`. Keep each entry's **full relative path** — do *not* collapse to
  the top-level component (git already returns the minimal set: fully-ignored
  dirs as `dir/`, otherwise individual ignored paths).
- Ignored files are set aside (temp dir) before the bare flip / removal, then
  moved into the target worktree once it exists. Both the set-aside and the
  restore are **path-preserving** (`mkdir -p` the parent first), so an ignored
  file nested in a *tracked* directory (e.g. `worker/node_modules/`) drops back
  inside the worktree's recreated tracked dir instead of colliding with it.
  Empty staging scaffolding is removed afterward.
- All `mv` operations are same-filesystem (cheap) — `node_modules/` etc. move
  instantly rather than being regenerated.

  > **Bug fixed (post-v1):** the original code collapsed ignored paths to their
  > top-level component, so a tracked dir containing ignored files was moved
  > wholesale; the worktree checkout then recreated the tracked copy and the
  > restore failed with `mv: cannot overwrite ... Directory not empty`, leaving a
  > `.git-wt-ignored.*` staging dir behind. Covered by
  > `test_migrate_handles_ignored_inside_tracked_dir`.

## Verification (all passing)

1. `bash -n git-wt` (syntax). `shellcheck` if available.
2. **init (empty):** `.git/` + empty unborn `main/`.
3. **init (non-empty):** pre-existing files moved into `main/`, untracked.
4. **init guard:** re-run aborts (`.git` exists).
5. **migrate (local, multi-branch + ignored):** dry-run plan, then `-y`; all
   branches → worktree folders; `.env`/`node_modules/` land in the current
   branch's worktree; dirty tree is rejected first.
5a. **migrate (ignored inside a tracked dir):** ignored files nested in a tracked
   directory (e.g. `worker/node_modules/`) are restored at the same relative path
   with no collision and no leftover staging dir.
6. **migrate (remote clone):** `remote.origin.fetch`, branch upstreams, and
   `origin/HEAD` all **unchanged** before vs after.
7. **migrate resume:** interrupt mid-loop (or pre-create one worktree), re-run →
   completes remaining branches; fully-migrated re-run reports "nothing to do".
8. **dirty abort:** uncommitted change → aborts and lists the file.
9. **broken remote:** bad refspec / missing `origin/HEAD` → warn-only, no writes.
10. **add (local branch):** sibling worktree lands at `<container>/<branch>` —
   correct even when run from inside another (nested) worktree.
11. **add (remote-only-but-fetched branch):** creates a tracking branch with no
   network.
12. **add (new branch):** created from `HEAD`, and from an explicit `--from <ref>`.
13. **add (.env copy):** a git-ignored `.env` in the source worktree is copied
   into the new worktree; `--no-copy-ignored` suppresses it; an existing `.env`
   is never overwritten.
14. **add guards:** existing worktree → prints its path and exits 0; an occupied
   non-worktree dir → aborts without clobbering.
15. **add dry-run:** prints the plan and creates nothing.

## Files

- `git-wt` — the script.
- `README.md` — usage + install.
- `docs/PLAN.md` — this document.
