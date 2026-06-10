# Tests for `git wt add`.

# Stand up a bare-repo + worktree layout in cwd (main/ only) and stay at the
# container root. Mirrors what `migrate` produces.
make_layout() {
  make_repo "$@"
  gitwt migrate -y >/dev/null
}

test_add_creates_new_branch_from_head() {
  sandbox
  make_layout
  gitwt add feature/x >/dev/null
  assert_file feature/x
  assert_eq "$(git -C feature/x rev-parse --abbrev-ref HEAD)" "feature/x"
}

test_add_anchors_to_container_from_inside_worktree() {
  # The key win over built-in: run from inside main/, the new worktree must be a
  # sibling at the container root, NOT nested under main/.
  sandbox
  make_layout
  ( cd main && gitwt add feature/y >/dev/null )
  assert_file feature/y          # sibling at container
  assert_absent main/feature/y   # not nested under main/
}

test_add_checks_out_existing_local_branch() {
  sandbox
  make_layout
  git -C main branch feat/a
  gitwt add feat/a >/dev/null
  assert_file feat/a
  assert_eq "$(git -C feat/a rev-parse --abbrev-ref HEAD)" "feat/a"
}

test_add_tracks_remote_branch_offline() {
  sandbox
  git init -q --bare -b main origin.git
  git clone -q origin.git seed
  ( cd seed && echo hi > f && git add -A && git commit -qm init && git push -q origin main \
      && git checkout -q -b feat/remote && echo x > g && git add -A && git commit -qm r \
      && git push -q origin feat/remote )
  git clone -q origin.git clone
  cd clone
  git fetch -q origin
  gitwt migrate -y >/dev/null            # only main/ (feat/remote is remote-only)
  assert_absent feat/remote
  gitwt add feat/remote >/dev/null
  assert_file feat/remote
  assert_eq "$(git -C feat/remote rev-parse --abbrev-ref HEAD)" "feat/remote"
  assert_eq "$(git -C feat/remote rev-parse --abbrev-ref 'feat/remote@{upstream}')" "origin/feat/remote"
}

test_add_uses_from_ref_for_new_branch() {
  sandbox
  make_repo                                   # commit 1 ("init") on main
  local first; first="$(git rev-parse HEAD)"
  echo two > f2 && git add -A && git commit -qm second   # commit 2 (still a normal repo)
  gitwt migrate -y >/dev/null
  gitwt add feature/old --from "$first" >/dev/null
  assert_eq "$(git -C feature/old rev-parse HEAD)" "$first"   # branched at commit 1, not HEAD
}

test_add_copies_ignored_env_and_skips_heavy() {
  sandbox
  make_repo
  printf 'node_modules/\n.env\n' > .gitignore
  git add -A && git commit -qm gi
  gitwt migrate -y >/dev/null
  echo "SECRET=1" > main/.env
  mkdir -p main/node_modules/x && echo y > main/node_modules/x/i.js
  local out; out="$(gitwt add feature/x 2>&1)"
  assert_file feature/x/.env                 # light ignored file copied
  assert_absent feature/x/node_modules       # heavy dir skipped
  assert_contains "$out" "node_modules"      # hint mentions it
  assert_contains "$out" "npm install"
}

test_add_copy_all_includes_heavy() {
  sandbox
  make_repo
  printf 'node_modules/\n' > .gitignore
  git add -A && git commit -qm gi
  gitwt migrate -y >/dev/null
  mkdir -p main/node_modules/x && echo y > main/node_modules/x/i.js
  gitwt add feature/x --copy-all >/dev/null
  assert_file feature/x/node_modules/x/i.js
}

test_add_no_copy_ignored() {
  sandbox
  make_repo
  printf '.env\n' > .gitignore
  git add -A && git commit -qm gi
  gitwt migrate -y >/dev/null
  echo "SECRET=1" > main/.env
  gitwt add feature/x --no-copy-ignored >/dev/null
  assert_absent feature/x/.env
}

test_add_aborts_outside_bare_layout() {
  sandbox
  make_repo                        # plain (non-bare) repo
  assert_fails gitwt add feature/x
  local out; out="$(gitwt add feature/x 2>&1 || true)"
  assert_contains "$out" "migrate"
}

test_add_noops_when_worktree_exists() {
  sandbox
  make_layout
  local out; out="$(gitwt add main)"
  assert_contains "$out" "Already present"
  assert_ok gitwt add main         # exits 0
}

test_add_aborts_when_path_occupied() {
  sandbox
  make_layout
  mkdir -p feature/x && touch feature/x/keep   # occupy target, not a worktree
  assert_fails gitwt add feature/x
}

test_add_dry_run_changes_nothing() {
  sandbox
  make_layout
  gitwt add feature/x --dry-run >/dev/null
  assert_absent feature/x
}

test_add_no_branch_noninteractive_aborts() {
  sandbox
  make_layout
  assert_fails gitwt add </dev/null   # no branch + non-tty stdin
}
