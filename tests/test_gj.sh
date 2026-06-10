# Tests for `gj` — the discovery core `gj-find` (pure/testable) and that gj.sh
# defines the shell function. The interactive fzf pick + cd in gj() needs a tty
# and changes cwd, so it isn't unit-tested here.

GJFIND="$ROOT/gj-find"

test_gj_scripts_syntax_valid() {
  assert_ok bash -n "$GJFIND"
  assert_ok bash -n "$ROOT/gj.sh"
}

test_gjfind_finds_normal_repo() {
  sandbox
  git init -q repoA
  local out; out="$("$GJFIND" .)"
  assert_contains "$out" "./repoA"
}

test_gjfind_finds_nested_repos() {
  sandbox
  git init -q a
  mkdir -p x/y && git init -q x/y/b
  local out; out="$("$GJFIND" .)"
  assert_contains "$out" "./a"
  assert_contains "$out" "./x/y/b"
}

test_gjfind_finds_bare_layout_container() {
  sandbox
  git init -q --bare container/.git
  local out; out="$("$GJFIND" .)"
  assert_contains "$out" "./container"
}

test_gjfind_skips_node_modules() {
  sandbox
  mkdir -p node_modules/pkg && git init -q node_modules/pkg/buried
  git init -q real
  local out; out="$("$GJFIND" .)"
  assert_contains "$out" "./real"
  [[ "$out" != *node_modules* ]] || fail "should not descend into node_modules: $out"
}

test_gjfind_respects_max_depth() {
  sandbox
  mkdir -p deep/a/b && git init -q deep/a/b/r     # .git sits several levels down
  local shallow deep
  shallow="$(GJ_MAX_DEPTH=2 "$GJFIND" .)"
  deep="$(GJ_MAX_DEPTH=8 "$GJFIND" .)"
  assert_eq "$shallow" "" "shallow depth should not reach the deep repo"
  assert_contains "$deep" "deep/a/b/r"
}

test_gjfind_honours_gj_roots_env() {
  sandbox
  git init -q one/repo1
  git init -q two/repo2
  local out; out="$(GJ_ROOTS="one:two" "$GJFIND")"
  assert_contains "$out" "one/repo1"
  assert_contains "$out" "two/repo2"
}

test_gjfind_empty_when_no_repos() {
  sandbox
  mkdir plain
  local out; out="$("$GJFIND" .)"
  assert_eq "$out" ""
}

test_gj_sh_defines_function() {
  source "$ROOT/gj.sh"
  assert_ok declare -F gj
}
