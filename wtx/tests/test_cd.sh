# Tests for the WTX_CD_FILE contract that the `wt` shell wrapper depends on.
#
# When WTX_CD_FILE points at a file, wtx-tool writes the absolute path of the
# worktree to cd into — but only on success paths that created a place to work,
# and never under --dry-run or when the var is unset.

# Stand up a bare-repo + worktree layout in cwd (main/ only), at the container.
make_layout() {
  make_repo "$@"
  wtxtool migrate -y >/dev/null
}

# run_capture_cd SUBCMD... — run wtx-tool with WTX_CD_FILE set to a temp file
# and print whatever it wrote there (empty if nothing). The temp file lives in
# the sandbox, so it's cleaned up with the rest of the test.
run_capture_cd() {
  local f; f="$(mktemp "${TMPDIR:-/tmp}/wtxtool-cd.XXXXXX")"
  WTX_CD_FILE="$f" wtxtool "$@" >/dev/null 2>&1 || true
  cat "$f"
  rm -f "$f"
}

test_add_writes_absolute_cd_path() {
  sandbox
  make_layout
  local container; container="$(pwd)"
  local got; got="$(run_capture_cd add feature/x)"
  assert_eq "$got" "$container/feature-x"     # absolute, flattened folder
}

test_init_writes_absolute_cd_path() {
  sandbox
  local container; container="$(pwd)"
  local got; got="$(run_capture_cd init main)"
  assert_eq "$got" "$container/main"
}

test_migrate_writes_current_branch_cd_path() {
  sandbox
  make_repo                                    # on main, normal repo
  local container; container="$(pwd)"
  local got; got="$(run_capture_cd migrate -y)"
  assert_eq "$got" "$container/main"
}

test_dry_run_writes_nothing() {
  sandbox
  make_layout
  local got; got="$(run_capture_cd add feature/x --dry-run)"
  assert_eq "$got" ""                          # previewed, nothing to cd into
  assert_absent feature-x                       # and indeed nothing created
}

test_already_present_writes_nothing() {
  sandbox
  make_layout                                   # main/ already has a worktree
  local got; got="$(run_capture_cd add main)"
  assert_eq "$got" ""                           # no-op re-run leaves you put
}

test_already_migrated_writes_nothing() {
  sandbox
  make_layout                                   # already a bare layout
  local got; got="$(run_capture_cd migrate -y)" # resume with nothing to do
  assert_eq "$got" ""
}

test_unset_var_leaves_output_unchanged() {
  # Without the var, wtx-tool must behave exactly as before: the human 'cd <path>'
  # hint is printed (and obviously nothing is written anywhere).
  sandbox
  make_layout
  local out; out="$(wtxtool add feature/x)"
  assert_contains "$out" "cd "                  # plain hint still shown
}

test_wrapped_suppresses_cd_hint() {
  # When wrapped, the redundant 'cd <path>' hint is dropped (you'll be taken
  # there automatically), but the heavy-dir rebuild hints remain.
  sandbox
  make_repo
  printf 'node_modules/\n' > .gitignore
  git add -A && git commit -qm gi
  wtxtool migrate -y >/dev/null
  mkdir -p main/node_modules/x && echo y > main/node_modules/x/i.js
  local f; f="$(mktemp "${TMPDIR:-/tmp}/wtxtool-cd.XXXXXX")"
  local out; out="$(WTX_CD_FILE="$f" wtxtool add feature/x 2>&1)"
  rm -f "$f"
  assert_contains "$out" "node_modules"         # heavy-dir hint kept
  [[ "$out" != *"cd "* ]] || fail "expected no 'cd ' hint when wrapped, got: $out"
}
