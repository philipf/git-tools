# shell-init.sh — shell wrappers for the git-tools commands.
#
# These are the bits that must live in your shell (not in a standalone binary)
# because a child process can't change its parent shell's working directory.
# Each wrapper runs the real tool, then cd's where it points.
#
# Install: source this from your shell rc (~/.zshrc / ~/.bashrc — works in both):
#
#   source ~/projects/git-tools/shell-init.sh
#
# The tools themselves (wtx-tool, gj-pick) must be on your PATH — see
# wtx/README.md and gj/README.md for those install steps.

# wtx — run wtx-tool, then cd into the worktree it creates (add/init/migrate).
# wtx-tool writes the target path to $WTX_CD_FILE on success; we read it back.
# Plain `wtx-tool …` (var unset) is unaffected and just prints a cd hint.
wtx() {
  local f d
  f=$(mktemp) || {
    wtx-tool "$@"
    return
  }
  WTX_CD_FILE="$f" wtx-tool "$@"
  local rc=$?
  d=$(cat "$f" 2>/dev/null)
  rm -f "$f"
  [ -n "$d" ] && [ -d "$d" ] && cd "$d"
  return $rc
}
#
# gj — fuzzy-pick a git repo/worktree and cd into it (gj-pick prints the path).
gj() {
  local d
  d=$(gj-pick "$@") || return
  [ -n "$d" ] && cd "$d"
}

# gjj — same as gj, but scoped to the current directory.
gjj() { gj --cwd "$@"; }
