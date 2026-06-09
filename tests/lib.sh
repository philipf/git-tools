# lib.sh — tiny zero-dependency test helpers for git-wt.
#
# A "test" is any shell function named test_* in a tests/test_*.sh file.
# run.sh sources every test file, then runs each test_* function in its own
# subshell. A test fails by calling fail() (which exits non-zero); otherwise it
# passes. Assertions below all funnel through fail().

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITWT="$ROOT/git-wt"

# Run the tool under test.
gitwt() { "$GITWT" "$@"; }

# fail MSG — abort the current test with a message.
fail() { printf '    %s%s\n' "${RED:-}✗ ${RST:-}" "$*" >&2; exit 1; }

# sandbox — fresh temp dir as cwd, git config isolated from the real machine,
# auto-removed when the test subshell exits. Sets a default identity and
# init.defaultBranch=main so tests are reproducible regardless of the host.
sandbox() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/gitwt-test.XXXXXX")"
  # Bake the path into the trap so cleanup doesn't depend on $d still being in
  # scope (it's local) when the subshell exits under `set -u`.
  trap "rm -rf '$d'" EXIT
  cd "$d"
  export GIT_CONFIG_GLOBAL="$d/.gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  git config -f "$GIT_CONFIG_GLOBAL" init.defaultBranch main
  git config -f "$GIT_CONFIG_GLOBAL" user.email  test@example.com
  git config -f "$GIT_CONFIG_GLOBAL" user.name   test
  git config -f "$GIT_CONFIG_GLOBAL" protocol.file.allow always
}

# make_repo — a normal repo in cwd: one commit on main, plus any extra branches
# passed as arguments. Example: make_repo feat/a feat/b
make_repo() {
  git init -q -b main
  echo hello > app.js
  git add -A && git commit -qm init
  local b
  for b in "$@"; do git branch "$b"; done
}

# Assertions ----------------------------------------------------------------
assert_eq()       { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1] ${3:-}"; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected to contain [$2], got: $1"; }
assert_file()     { [[ -e "$1" ]] || fail "expected to exist: $1"; }
assert_absent()   { [[ ! -e "$1" ]] || fail "expected to be absent: $1"; }
assert_ok()       { "$@" >/dev/null 2>&1 || fail "expected success: $*"; }
assert_fails()    { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }
