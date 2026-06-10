# gj.sh — fuzzy-jump to a local git repo, then optionally run a command.
#
# Source this from your shell rc (bash/zsh):
#   source /path/to/gj.sh
# and make sure `gj-find` (the discovery core) is on your PATH.
#
# Usage:
#   gj                  # pick a repo with fzf, cd into it
#   gj lazygit          # pick a repo, cd into it, then run `lazygit` there
#   gj git status -sb   # any command + args after the pick
#
# Why a shell function (not just a script): a child process can't change its
# parent shell's working directory, so the `cd` must run in your shell. `gj`
# delegates discovery to `gj-find` and does the pick + cd itself.
gj() {
  if ! command -v gj-find >/dev/null 2>&1; then
    printf 'gj: gj-find not found on PATH\n' >&2
    return 1
  fi

  local dir
  if command -v fzf >/dev/null 2>&1; then
    # --select-1: auto-pick when there's exactly one repo.
    # --exit-0:   exit quietly when there are none.
    dir="$(gj-find | fzf --select-1 --exit-0 --reverse --height=40% \
            --prompt='git repo> ' \
            --preview 'git -C {} -c color.status=always status -sb 2>/dev/null; \
                       echo; git -C {} log --oneline -5 2>/dev/null')" || return
  else
    # No fzf: fall back to a numbered menu.
    local -a repos=()
    local r
    while IFS= read -r r; do repos+=("$r"); done < <(gj-find)
    if (( ${#repos[@]} == 0 )); then
      printf 'gj: no git repos found\n' >&2
      return 1
    fi
    local PS3='git repo> '
    select dir in "${repos[@]}"; do [[ -n "$dir" ]] && break; done
  fi

  [[ -n "$dir" ]] || return 0          # cancelled / nothing selected
  cd "$dir" || return 1
  (( $# )) && "$@"                      # run the trailing command, if any
}
