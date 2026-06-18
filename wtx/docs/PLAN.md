# Plan: `wtx-tool` — bare-repo + worktree layout tool

> Design record for `wtx-tool`. Decisions below were settled in a Q&A session and
> verified end-to-end against real repos. Kept for future reference.

## Context

The bare-repo + worktree layout puts one container folder holding the bare
object store (`.git/`) plus one sibling folder per checked-out branch. Setting
it up by hand is a fiddly multi-step dance (bare init/clone, refspec fix, fetch,
per-worktree upstream). `wtx-tool` automates the two entry points:

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

- **Single bash file** `wtx-tool` (no extension), `#!/usr/bin/env bash`,
  `set -euo pipefail`.
- Subcommand **dispatcher**: `init`, `migrate`, `help` (room for future
  `add`/`list`/`remove`); shared helper functions at the top.
- Named `wtx-tool`, invoked as **`wtx …`** via a shell wrapper. The wrapper
  function is `wtx()`; the binary is `wtx-tool` so the function doesn't shadow
  itself when it calls through.
  > **Superseded (2026-06-18).** Originally named `git-wt` so git's
  > `git foo → git-foo` mapping exposed it as the subcommand `git wt`; renamed to
  > the standalone `wtx` to avoid colliding with worktrunk's `wt` command.
- **Install:** symlink `~/.local/bin/wtx-tool → repo/wtx-tool` (that dir is on PATH).

## `wtx init [branch]`

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

## `wtx migrate [--dry-run] [-y]`

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
  > `.wtx-ignored.*` staging dir behind. Covered by
  > `test_migrate_handles_ignored_inside_tracked_dir`.

## Verification (all passing)

1. `bash -n wtx-tool` (syntax). `shellcheck` if available.
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

## Files

- `wtx-tool` — the script.
- `README.md` — usage + install.
- `docs/PLAN.md` — this document.
