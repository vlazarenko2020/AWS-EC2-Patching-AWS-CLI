#!/usr/bin/env bash
# Lints all shell scripts in the repo with shellcheck.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

status=0
while IFS= read -r -d '' script; do
    echo "== ${script} =="
    shellcheck "${script}" || status=1
done < <(find . -name '*.sh' -not -path './.git/*' -print0)

exit "${status}"
