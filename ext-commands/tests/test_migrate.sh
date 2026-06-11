# Tests for `git wt migrate`.

test_migrate_aborts_when_dirty() {
  sandbox
  make_repo
  echo change >> app.js          # unstaged change
  assert_fails gitwt migrate -y
  assert_eq "$(git rev-parse --is-bare-repository)" "false"   # untouched
}

test_migrate_dry_run_changes_nothing() {
  sandbox
  make_repo feat/a
  local before; before="$(ls -A)"
  gitwt migrate --dry-run >/dev/null
  assert_eq "$(ls -A)" "$before"
  assert_eq "$(git rev-parse --is-bare-repository)" "false"
}

test_migrate_creates_worktree_per_branch() {
  sandbox
  make_repo feat/a feat/b
  gitwt migrate -y >/dev/null
  assert_eq "$(git rev-parse --is-bare-repository)" "true"
  assert_file main
  assert_file feat/a
  assert_file feat/b
  assert_absent app.js           # committed root file removed
}

test_migrate_moves_ignored_files_into_worktree() {
  sandbox
  make_repo
  printf 'node_modules/\n.env\n' > .gitignore
  git add -A && git commit -qm gitignore
  mkdir -p node_modules/foo && echo x > node_modules/foo/i.js
  echo "SECRET=1" > .env
  gitwt migrate -y >/dev/null
  assert_file main/node_modules/foo/i.js
  assert_file main/.env
  assert_absent node_modules     # not stranded at container root
  assert_absent .env
}

test_migrate_handles_ignored_inside_tracked_dir() {
  # Regression: a tracked directory that also contains ignored files. The
  # ignored bits must land back inside the recreated tracked dir, not collide
  # with it. (Previously failed: "mv: cannot overwrite ... Directory not empty".)
  sandbox
  make_repo
  printf 'node_modules/\n__pycache__/\n' > .gitignore
  mkdir -p worker/src && echo 'tracked' > worker/src/index.js
  echo '{}' > worker/package.json
  git add -A && git commit -qm worker
  # ignored content nested inside the tracked 'worker' dir
  mkdir -p worker/node_modules/dep && echo x > worker/node_modules/dep/i.js
  gitwt migrate -y >/dev/null
  assert_file main/worker/src/index.js                 # tracked file restored
  assert_file main/worker/package.json                 # tracked file restored
  assert_file main/worker/node_modules/dep/i.js        # ignored file re-merged
  # no staging dir left behind
  local leftover; leftover="$(compgen -G '.git-wt-ignored.*' || true)"
  assert_eq "$leftover" "" "staging dir not cleaned up"
  # The worktree still sees node_modules as ignored (clean status).
  assert_eq "$(git -C main status --porcelain)" ""
}

test_migrate_resumes_after_partial() {
  sandbox
  make_repo feat/a feat/b
  # Simulate a migrate that died after flipping bare + creating only main/.
  git config core.bare true
  rm -f app.js
  git worktree add -q main main
  gitwt migrate -y >/dev/null
  assert_file main
  assert_file feat/a
  assert_file feat/b
}

test_migrate_noop_when_already_complete() {
  sandbox
  make_repo feat/a
  gitwt migrate -y >/dev/null
  local out; out="$(gitwt migrate -y)"
  assert_contains "$out" "Already migrated"
}

test_migrate_leaves_remote_config_unchanged() {
  sandbox
  git init -q --bare -b main origin.git
  git clone -q origin.git seed
  ( cd seed && echo hi > f.txt && git add -A && git commit -qm init \
      && git push -q origin main )
  git clone -q origin.git clone
  cd clone
  local before_refspec before_head before_up
  before_refspec="$(git config --get remote.origin.fetch)"
  before_head="$(git symbolic-ref refs/remotes/origin/HEAD)"
  before_up="$(git rev-parse --abbrev-ref main@{upstream})"
  gitwt migrate -y >/dev/null
  assert_eq "$(git config --get remote.origin.fetch)" "$before_refspec" "refspec changed"
  assert_eq "$(git symbolic-ref refs/remotes/origin/HEAD)" "$before_head" "origin/HEAD changed"
  assert_eq "$(git -C main rev-parse --abbrev-ref main@{upstream})" "$before_up" "upstream changed"
}

test_migrate_warns_on_broken_remote() {
  sandbox
  git init -q --bare -b main origin.git
  git clone -q origin.git seed
  ( cd seed && echo hi > f.txt && git add -A && git commit -qm init \
      && git push -q origin main )
  git clone -q origin.git clone
  cd clone
  git config remote.origin.fetch "+refs/heads/main:refs/remotes/origin/main"
  git symbolic-ref -d refs/remotes/origin/HEAD
  local out; out="$(gitwt migrate -y 2>&1)"
  assert_contains "$out" "remote.origin.fetch looks off"
  assert_contains "$out" "origin/HEAD is not set"
}
