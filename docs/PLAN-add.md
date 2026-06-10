# Plan: `git wt add` — create one worktree in an existing layout

> Design record for a proposed `add` subcommand. Standalone for now; folds into
> `docs/PRD.md` / `docs/PLAN.md` once settled and implemented. Status: **draft**.

## Context

`git-wt` currently has `init` and `migrate` — the two ways to *stand up* the
bare-repo + worktree layout:

```
myrepo/
├── .git/        ← bare object store (named .git directly)
├── main/        ← worktree for branch `main`
└── feature/x/   ← worktree for branch `feature/x` (verbatim, nested ok)
```

Once the layout exists, the day-to-day move is "give me a worktree for branch
X". Today that means raw `git worktree add`. `add` wraps it so the layout's
invariants hold automatically and the new worktree is immediately runnable.

## Why wrap `git worktree add` at all?

A wrapper only earns its place if it removes friction the built-in can't. Three
concrete gaps, verified against real repos:

1. **Placement (the big one).** `git worktree add <path>` resolves a relative
   `<path>` against the **current shell directory**, not the container. In this
   layout that misfires: run from inside `main/`,
   `git worktree add feature/x feature/x` creates **`main/feature/x/`** — nested
   under `main`, not a sibling of `.git/`. To get it right by hand you must type
   the branch twice *and* compute the correct `../` prefix (worse from an
   already-nested worktree like `feature/x/`, which needs `../../`). `add`
   anchors to the container and derives the folder from the branch name, so one
   argument always lands in the right place.

2. **Runnable worktree.** A fresh built-in worktree is clean — no `.env`, no
   local config — so it can't actually run until you hand-copy those. This is the
   pain point for the project's stated use case (parallel agents/editors, each in
   its own worktree). `migrate` already solved the sibling problem (move ignored
   files into a worktree); `add` does the new-worktree equivalent: copy
   `.env`-style ignored files in by default.

3. **Predictable, offline branch resolution.** The built-in's new-branch DWIM
   depends on `worktree.guessRemote` and can reach for the network. `add` gives
   one explicit rule and never touches the network.

What it is **not**: a feature-richer `git worktree add`. It deliberately covers
the one-worktree-at-a-time happy path for this layout. Power users can still call
`git worktree add` directly.

## Surface

```
git wt add [<branch>] [--from <ref>]
           [--no-copy-ignored] [--copy-ignored <glob>]...
           [-n|--dry-run] [-h|--help]
```

- `<branch>` — branch to materialise. Required for v1 (interactive pick is a
  later, `switch`-adjacent concern).
- `--from <ref>` — base for a brand-new branch (default `HEAD`). Ignored when the
  branch already exists locally or as a remote-tracking branch.
- `--copy-ignored <glob>` — extra ignored-file glob to copy (repeatable); adds to
  the default set.
- `--no-copy-ignored` — copy nothing.
- `-n`/`--dry-run` — print the plan, change nothing.

`add` is additive and non-destructive, so there is **no confirm prompt** and no
`-y` (unlike `migrate`).

## Behaviour

1. **Anchor to the container.** `container = dirname(git rev-parse
   --git-common-dir)`. The new worktree always lands at `<container>/<branch>`,
   regardless of CWD.

2. **Resolve the branch (offline):**
   - local branch exists →
     `git worktree add <container>/<branch> <branch>`
   - else a remote-tracking branch `<remote>/<branch>` exists (prefer `origin`) →
     `git worktree add --track -b <branch> <container>/<branch> <remote>/<branch>`
   - else a new branch →
     `git worktree add -b <branch> <container>/<branch> <base>`,
     where `base = --from` else `HEAD`.

3. **Guards:**
   - a worktree for the branch already exists → print its path, exit **0**
     (nothing to do).
   - `<container>/<branch>` exists but is **not** that worktree → **abort**
     (never clobber).

4. **Copy ignored env files** (default on). Source worktree = the worktree the
   CWD is in; if outside any worktree, the **default branch's** worktree
   (`init.defaultBranch` → else first worktree). For each pattern in the copy set
   (default `.env*` at the worktree root; extend with `--copy-ignored`), copy
   files that are **(a)** git-ignored in the source and **(b)** absent in the new
   worktree. Never overwrite.

5. **No network, no remote writes.** Remote-tracking resolution reads only
   already-fetched refs.

6. **Report.** Print the resulting tree (reuse `print_tree`) + the next step
   (`cd <container>/<branch>`).

## Requirements (EARS)

> `D` prefix = *a**D**d* (`A` is taken by Assumptions in the main PRD).

- **D1 (Ubiquitous).** `add` shall create a single worktree as a sibling of
  `.git/`, named exactly after its branch (verbatim, nested for slashes).
- **D2 (Ubiquitous).** `add` shall anchor placement to the container (parent of
  `git rev-parse --git-common-dir`), so it is correct regardless of CWD,
  including from inside a nested worktree.
- **D3 (Unwanted).** If not inside a git repository, `add` shall abort.
- **D4 (Event-driven).** When the branch exists locally, `add` shall check it out
  into the new worktree.
- **D5 (Event-driven).** When the branch is absent locally but a remote-tracking
  branch matches, `add` shall create a local tracking branch using only
  already-fetched refs.
- **D6 (Event-driven).** When the branch is absent everywhere, `add` shall create
  it from `--from <ref>` (default `HEAD`).
- **D7 (Unwanted).** If a worktree for the branch already exists, `add` shall
  print its path and exit successfully without changes.
- **D8 (Unwanted).** If the target folder exists but is not that worktree, `add`
  shall abort without clobbering it.
- **D9 (State-driven).** While git-ignored files matching the copy set (default
  `.env*` at the worktree root) exist in the source worktree, `add` shall copy
  them into the new worktree.
- **D10 (Optional).** Where `--no-copy-ignored` is given, `add` shall copy
  nothing; where `--copy-ignored <glob>` is given (repeatable), it shall extend
  the copy set.
- **D11 (Ubiquitous).** `add` shall copy only genuinely git-ignored files that
  match the set, and shall never overwrite an existing file.
- **D12 (Event-driven).** When `--dry-run`/`-n` is given, `add` shall print the
  plan and change nothing.
- **D13 (Ubiquitous).** `add` shall not contact or mutate any remote, and shall
  be non-destructive (no confirm prompt).
- **D14 (Event-driven).** When `add` finishes, it shall print the resulting
  layout and the next step.

Inherits the existing non-functionals: offline (N1), non-destructive (N2),
fail-fast `set -euo pipefail` (N4), colour-on-tty (N5).

## Key implementation notes

- Container / common-dir: `git rev-parse --git-common-dir` → parent. Works from
  the bare container root or any worktree.
- Existing-worktree lookup: `git worktree list --porcelain`; match
  `branch refs/heads/<branch>` or `worktree <container>/<branch>`.
- Remote-tracking existence: `git show-ref --verify --quiet
  refs/remotes/origin/<branch>` (iterate remotes if origin lacks it).
- Ignored check before copying: `git -C <source> check-ignore -q <file>`. Default
  glob stays at the worktree root to avoid surprises.
- **Copy, not symlink:** each worktree's `.env` stays independent, so parallel
  agents can diverge config without clobbering a shared file. A `--link` flag
  (symlinks) is a possible later extension, out of scope now.
- Reuses existing helpers — `default_branch_name`, `print_tree`, colour, `run`
  (honours `DRY_RUN`), `die` — and slots into the dispatcher beside
  `init`/`migrate`.

## Verification (to add to `tests/`)

1. **local branch:** worktree lands at `<container>/<branch>`, correct even when
   run from inside another (nested) worktree.
2. **remote-only-but-fetched branch:** creates a tracking branch, no network.
3. **new branch:** created from `HEAD`, and from an explicit `--from <ref>`.
4. **.env copy:** a git-ignored `.env` in the source worktree is copied in;
   `--no-copy-ignored` suppresses it; an existing `.env` is never overwritten.
5. **guards:** existing worktree → prints path, exit 0; occupied non-worktree dir
   → abort.
6. **dry-run:** prints the plan, creates nothing.

## Open questions

- **Default copy set:** `.env*` only, or also things like `.envrc`, `.tool-versions`?
- **Copy vs symlink default:** copy proposed; revisit if shared-secret workflows
  prefer symlinks.
- **No-arg behaviour:** error for now; later an interactive pick could overlap
  with the parked `switch` command.
- **Non-bare repos:** `add` is designed for the bare layout. Anchoring still
  works in a normal repo, but worktrees would nest under the main worktree —
  warn, or just document it as layout-only?
