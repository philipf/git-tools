#!/usr/bin/env bash
#
# run.sh — run the git-wt test suite (zero dependencies; just bash + git).
#
#   ./tests/run.sh            # run everything
#   ./tests/run.sh init       # run only test files matching *init*
#
# A test is any function named test_* in a tests/test_*.sh file. Each runs in
# its own subshell with an isolated, throwaway git environment (see lib.sh).

set -uo pipefail
cd "$(dirname "$0")"

if [[ -t 1 ]]; then
  GRN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RST=$'\033[0m'
else
  GRN=''; RED=''; DIM=''; RST=''
fi
export GRN RED DIM RST

source ./lib.sh

filter="${1:-}"
shopt -s nullglob
for f in test_*.sh; do
  [[ -n "$filter" && "$f" != *"$filter"* ]] && continue
  # shellcheck disable=SC1090
  source "./$f"
done

mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)
if (( ${#tests[@]} == 0 )); then
  echo "no tests found"; exit 1
fi

pass=0; failc=0
for t in "${tests[@]}"; do
  # Capture each test's output; show it only when the test fails.
  if out="$( "$t" 2>&1 )"; then
    printf '%s✓%s %s\n' "$GRN" "$RST" "$t"
    pass=$((pass + 1))
  else
    printf '%s✗ %s%s\n' "$RED" "$t" "$RST"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/      /'
    failc=$((failc + 1))
  fi
done

echo "${DIM}────────${RST}"
if (( failc == 0 )); then
  printf '%s%d passed%s\n' "$GRN" "$pass" "$RST"
else
  printf '%s%d passed, %d failed%s\n' "$RED" "$pass" "$failc" "$RST"
fi
(( failc == 0 ))
