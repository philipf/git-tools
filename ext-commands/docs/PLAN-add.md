# Plan: `git wt add` — create one worktree in an existing layout

> Design record for the `add` subcommand. Status: **implemented** in `git-wt`
> (`cmd_add`), covered by `tests/test_add.sh`.

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
           [--copy-all] [--no-copy-ignored]
           [-n|--dry-run] [-h|--help]
```

- `<branch>` — branch to materialise. **Optional**: when omitted, `add` shows an
  interactive picker of candidate branches that have no worktree yet (see below).
- `--from <ref>` — base for a brand-new branch (default `HEAD`). Ignored when the
  branch already exists locally or as a remote-tracking branch.
- `--copy-all` — also copy the normally-skipped heavy/regenerable dirs
  (`node_modules/`, `.venv/`, …), reflink-accelerated where the filesystem
  supports it.
- `--no-copy-ignored` — copy nothing.
- `-n`/`--dry-run` — print the plan, change nothing.

`add` is additive and non-destructive, so there is **no confirm prompt** and no
`-y` (unlike `migrate`).

## Behaviour

0. **Require the bare layout (hard error otherwise).** `add` only makes sense in
   a bare-repo + worktree layout. If `git config core.bare` is not `true`, abort
   and point at `git wt migrate`. (Use `core.bare`, **not**
   `--is-bare-repository`: the latter returns `false` from inside a worktree, so
   it would wrongly reject a valid layout — see impl notes.)

1. **Anchor to the container.** `container = dirname(git rev-parse
   --git-common-dir)`. The new worktree always lands at `<container>/<branch>`,
   regardless of CWD.

2. **Pick the branch.** If `<branch>` is given, use it. If omitted, show an
   **interactive picker** of candidate branches that have no worktree yet
   (local branches + remote-tracking branches, minus any already checked out).
   On a non-interactive stdin with no `<branch>`, abort asking for an explicit
   branch.

3. **Resolve the branch (offline):**
   - local branch exists →
     `git worktree add <container>/<branch> <branch>`
   - else a remote-tracking branch `<remote>/<branch>` exists (prefer `origin`) →
     `git worktree add --track -b <branch> <container>/<branch> <remote>/<branch>`
   - else a new branch →
     `git worktree add -b <branch> <container>/<branch> <base>`,
     where `base = --from` else `HEAD`.

4. **Guards:**
   - a worktree for the branch already exists → print its path, exit **0**
     (nothing to do).
   - `<container>/<branch>` exists but is **not** that worktree → **abort**
     (never clobber).

5. **Copy ignored files** (default on). Source worktree = the worktree the CWD is
   in; if outside any worktree, the **default branch's** worktree
   (`init.defaultBranch` → else first worktree). Copy **every top-level
   git-ignored entry** from the source into the new worktree **except** the
   built-in **skip-list** of heavy/regenerable dirs (`node_modules`, `.venv`,
   `venv`, `target`, `dist`, `build`, `out`, `.next`, `.nuxt`, `__pycache__`,
   `.cache`, `.gradle`, `coverage`, …). Only copy entries that are **(a)**
   git-ignored in the source and **(b)** absent in the new worktree — never
   overwrite. Copies use `cp --reflink=auto` so they are copy-on-write-cheap
   where the filesystem supports it (A2: same filesystem).
   - For each **skipped** heavy dir present in the source, print a reinstall hint
     derived from the project's lockfile (`pnpm-lock.yaml`→`pnpm install`,
     `yarn.lock`→`yarn`, `package-lock.json`→`npm install`, etc.).
   - `--copy-all` overrides the skip-list and copies the heavy dirs too
     (reflink-accelerated). `--no-copy-ignored` copies nothing.

6. **No network, no remote writes.** Remote-tracking resolution reads only
   already-fetched refs.

7. **Report.** Print the resulting tree (reuse `print_tree`), any reinstall
   hints, and the next step (`cd <container>/<branch>`).

## Requirements (EARS)

> `D` prefix = *a**D**d* (`A` is taken by Assumptions in the main PRD).

- **D1 (Ubiquitous).** `add` shall create a single worktree as a sibling of
  `.git/`, named exactly after its branch (verbatim, nested for slashes).
- **D2 (Ubiquitous).** `add` shall anchor placement to the container (parent of
  `git rev-parse --git-common-dir`), so it is correct regardless of CWD,
  including from inside a nested worktree.
- **D3 (Unwanted).** If not inside a git repository, `add` shall abort.
- **D3a (Unwanted).** If the repository is not a bare-repo + worktree layout
  (`git config core.bare` is not `true`), then `add` shall abort and point the
  user at `git wt migrate`.
- **D4 (Event-driven).** When the branch exists locally, `add` shall check it out
  into the new worktree.
- **D5 (Event-driven).** When the branch is absent locally but a remote-tracking
  branch matches, `add` shall create a local tracking branch using only
  already-fetched refs.
- **D6 (Event-driven).** When the branch is absent everywhere, `add` shall create
  it from `--from <ref>` (default `HEAD`).
- **D6a (Event-driven).** When `add` is run with no `<branch>` on an interactive
  terminal, it shall present a picker of candidate branches that have no worktree
  yet (local + remote-tracking) and act on the chosen one; on a non-interactive
  stdin it shall abort asking for an explicit branch.
- **D7 (Unwanted).** If a worktree for the branch already exists, `add` shall
  print its path and exit successfully without changes.
- **D8 (Unwanted).** If the target folder exists but is not that worktree, `add`
  shall abort without clobbering it.
- **D9 (State-driven).** While git-ignored entries exist at the source worktree
  root, `add` shall copy them into the new worktree, **except** entries on the
  built-in skip-list of heavy/regenerable dirs.
- **D9a (Event-driven).** When a skip-listed heavy dir is present in the source,
  `add` shall print a reinstall hint instead of copying it (the command derived
  from the project's lockfile where one is found).
- **D10 (Optional).** Where `--copy-all` is given, `add` shall also copy the
  skip-listed heavy dirs; where `--no-copy-ignored` is given, `add` shall copy
  nothing.
- **D11 (Ubiquitous).** `add` shall copy only genuinely git-ignored entries,
  shall never overwrite an existing file in the new worktree, and shall use
  copy-on-write (`cp --reflink=auto`) where the filesystem supports it.
- **D12 (Event-driven).** When `--dry-run`/`-n` is given, `add` shall print the
  plan and change nothing.
- **D13 (Ubiquitous).** `add` shall not contact or mutate any remote, and shall
  be non-destructive (no confirm prompt).
- **D14 (Event-driven).** When `add` finishes, it shall print the resulting
  layout, any reinstall hints, and the next step.

Inherits the existing non-functionals: offline (N1), non-destructive (N2),
fail-fast `set -euo pipefail` (N4), colour-on-tty (N5).

## Key implementation notes

- Layout check: `git config core.bare` (reads the shared common-dir config, so it
  is `true` from the container root **and** from inside any worktree).
  `git rev-parse --is-bare-repository` is the wrong probe — it returns `false`
  from inside a worktree and would reject a valid layout.
- Container / common-dir: `git rev-parse --git-common-dir` → parent. Works from
  the bare container root or any worktree.
- Existing-worktree lookup: `git worktree list --porcelain`; match
  `branch refs/heads/<branch>` or `worktree <container>/<branch>`.
- Remote-tracking existence: `git show-ref --verify --quiet
  refs/remotes/origin/<branch>` (iterate remotes if origin lacks it).
- Picker candidates (no-arg): local branches (`for-each-ref refs/heads`) and
  remote-tracking branches (`for-each-ref refs/remotes`, excluding `*/HEAD`),
  minus any branch that already has a worktree. Prefer `fzf` if on `PATH`, else a
  bash `select` menu. Require an interactive stdin (`[[ -t 0 ]]`).
- Ignored-entry copy: enumerate top-level entries in the source worktree, keep
  those that are git-ignored (`git -C <source> check-ignore -q <entry>`), drop
  skip-listed names (unless `--copy-all`), then `cp -a --reflink=auto` each into
  the new worktree only if the destination is absent (never overwrite).
- Skip-list is a script constant (regenerable dep/build/cache dirs). Reinstall
  hint maps lockfile → command (`pnpm-lock.yaml`→`pnpm install`,
  `yarn.lock`→`yarn`, `package-lock.json`→`npm install`, `requirements.txt` /
  `pyproject.toml`→the project's install step, …); fall back to a generic note.
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
4. **ignored copy:** a git-ignored `.env` in the source worktree is copied in;
   `--no-copy-ignored` suppresses it; an existing `.env` is never overwritten.
5. **skip-list + hint:** a git-ignored `node_modules/` is **not** copied and a
   reinstall hint is printed; `--copy-all` copies it.
6. **layout guard:** in a normal (non-bare) repo, `add` aborts pointing at
   `migrate` — including when run from inside a worktree (the `core.bare` probe,
   not `--is-bare-repository`).
7. **guards:** existing worktree → prints path, exit 0; occupied non-worktree dir
   → abort.
8. **picker:** no-arg on a non-interactive stdin aborts asking for a branch.
9. **dry-run:** prints the plan, creates nothing.

## Decisions (resolved)

- **Copy set:** copy all top-level git-ignored entries except a skip-list of
  heavy/regenerable dirs; print a reinstall hint per skipped dir; `--copy-all`
  forces them in (reflink-accelerated). Chosen over a minimal `.env*`-only
  allowlist (less "just works") and a size-threshold skip (less predictable).
- **Copy, not symlink:** independent per-worktree config; agents can diverge
  without clobbering a shared file.
- **No-arg behaviour:** interactive picker of worktree-less candidate branches;
  non-interactive stdin must pass an explicit branch.
- **Non-bare repos:** hard error pointing at `git wt migrate` — `add` is
  layout-only.

## Deferred / possible extensions

- `--link` for symlinking heavy dirs (e.g. a shared `node_modules`), for users
  who prefer one source of truth.
- Auto-running the detected install command (rather than only printing the hint).
- Extending/overriding the skip-list via config or a flag.
