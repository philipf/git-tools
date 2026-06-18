# Tests for `wtx init`.

test_syntax_is_valid() {
  assert_ok bash -n "$WTXTOOL"
}

test_help_and_noarg_exit_ok() {
  sandbox
  assert_ok wtxtool help
  assert_ok wtxtool          # no subcommand → prints usage, exits 0
}

test_unknown_subcommand_fails() {
  sandbox
  assert_fails wtxtool bogus
}

test_init_empty_dir() {
  sandbox
  wtxtool init >/dev/null
  assert_file .git
  assert_file main
  assert_eq "$(git -C .git rev-parse --is-bare-repository)" "true"
  # main is an unborn branch — no commits yet.
  assert_eq "$(git -C main rev-list --count --all)" "0"
}

test_init_moves_existing_files() {
  sandbox
  touch README.md
  mkdir src && touch src/a.js
  wtxtool init >/dev/null
  assert_file main/README.md
  assert_file main/src/a.js
  assert_absent README.md
  assert_absent src
}

test_init_aborts_when_git_exists() {
  sandbox
  wtxtool init >/dev/null
  assert_fails wtxtool init      # .git now exists → not brand-new
}

test_init_custom_branch_arg() {
  sandbox
  wtxtool init trunk >/dev/null
  assert_file trunk
  assert_absent main
}

test_init_respects_default_branch_config() {
  sandbox
  git config -f "$GIT_CONFIG_GLOBAL" init.defaultBranch dev
  wtxtool init >/dev/null
  assert_file dev
  assert_absent main
}

test_init_flattens_slashed_branch() {
  sandbox
  wtxtool init feature/x >/dev/null
  assert_file feature-x                       # folder flattened
  assert_absent feature/x                     # not nested
  assert_eq "$(git -C feature-x symbolic-ref --short HEAD)" "feature/x"  # branch keeps slash
}
