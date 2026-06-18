#!/usr/bin/env bash
#
# symlink-init.sh — install the git-tools commands onto your PATH.
#
# Symlinks the executables and the shell-init helper into a bin dir (default
# ~/.local/bin) using absolute paths, so they keep working regardless of where
# this repo is checked out. Run once per machine:
#
#   ./symlink-init.sh
#
# Then source the shell wrappers (wtx/gj/gjj) from your shell rc — point at the
# stable symlink, not the repo, so it's machine-independent:
#
#   [ -f ~/.local/bin/shell-init.sh ] && source ~/.local/bin/shell-init.sh
#
# Override the destination dir with: BINDIR=/some/dir ./symlink-init.sh

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bindir="${BINDIR:-$HOME/.local/bin}"

mkdir -p "$bindir"

# link TARGET NAME — symlink $bindir/NAME -> absolute TARGET (idempotent).
link() {
  local target="$1" dest="$bindir/$2"
  [ -e "$target" ] || { printf 'error: missing %s\n' "$target" >&2; exit 1; }
  ln -sfn "$target" "$dest"
  printf '  %s -> %s\n' "$dest" "$target"
}

printf 'Linking git-tools into %s:\n' "$bindir"
link "$repo/wtx/wtx-tool"  wtx-tool
link "$repo/gj/gj-pick"    gj-pick
link "$repo/wtc/wtc"       wtc
link "$repo/shell-init.sh" shell-init.sh

printf '\nDone.'
case ":$PATH:" in
  *":$bindir:"*) printf ' %s is on your PATH.\n' "$bindir" ;;
  *)             printf '\nwarning: %s is not on your PATH — add it.\n' "$bindir" ;;
esac
printf 'Add to your shell rc (if not already):\n'
printf '  [ -f %s/shell-init.sh ] && source %s/shell-init.sh\n' "$bindir" "$bindir"
