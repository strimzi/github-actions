#!/usr/bin/env bash
# Runs ShellCheck on all shell scripts and on the run: steps of composite actions.
# actionlint covers run: steps in workflows only, so composite actions need this.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

status=0

find .github -name '*.sh' -print0 | xargs -0 shellcheck -S warning || status=1

for action in .github/actions/*/*/action.yml; do
  steps=$(yq '.runs.steps | length' "$action")
  for ((i = 0; i < steps; i++)); do
    [ "$(yq ".runs.steps[$i] | has(\"run\")" "$action")" = "true" ] || continue
    # Expressions are evaluated before the shell runs, so replace them like actionlint does
    if ! out=$( { echo '#!/bin/bash'; yq ".runs.steps[$i].run" "$action" | sed -E 's/\$\{\{[^}]*\}\}/_expr_/g'; } | shellcheck -S warning -e SC2050,SC2154,SC2157,SC2194 -); then
      echo "${action}: step '$(yq ".runs.steps[$i].name" "$action")'"
      echo "$out"
      status=1
    fi
  done
done

exit $status
