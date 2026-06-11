# Tests for `git wt init`.

test_syntax_is_valid() {
  assert_ok bash -n "$GITWT"
}

test_help_and_noarg_exit_ok() {
  sandbox
  assert_ok gitwt help
  assert_ok gitwt          # no subcommand → prints usage, exits 0
}

test_unknown_subcommand_fails() {
  sandbox
  assert_fails gitwt bogus
}

test_init_empty_dir() {
  sandbox
  gitwt init >/dev/null
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
  gitwt init >/dev/null
  assert_file main/README.md
  assert_file main/src/a.js
  assert_absent README.md
  assert_absent src
}

test_init_aborts_when_git_exists() {
  sandbox
  gitwt init >/dev/null
  assert_fails gitwt init      # .git now exists → not brand-new
}

test_init_custom_branch_arg() {
  sandbox
  gitwt init trunk >/dev/null
  assert_file trunk
  assert_absent main
}

test_init_respects_default_branch_config() {
  sandbox
  git config -f "$GIT_CONFIG_GLOBAL" init.defaultBranch dev
  gitwt init >/dev/null
  assert_file dev
  assert_absent main
}
