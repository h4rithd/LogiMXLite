#!/bin/bash
# Fast checks for accidental private files and common credential formats.
set -euo pipefail
cd "$(dirname "$0")/.."

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    file_list="$(git ls-files)"
else
    # The owner's working copy intentionally has no .git directory.
    file_list="$(find . \( -path './.build' -o -path './dist' -o -path './.git' \) -prune -o -type f -print)"
fi

if printf '%s\n' "$file_list" | grep -Ei '(^|/)(settings\.db|settings\.json|backup\.json|\.env([.]|$)|[^/]+\.(p8|p12|pem|key|mobileprovision)|LogiMXLite_(Codex_Build_Prompt|Configuration_Analysis|sanitized_reference)\.[^/]+|reference\.json)$'; then
    echo 'Private or generated files are tracked.' >&2
    exit 1
fi

if rg -I -l --hidden -g '!dist/**' -g '!.build/**' -g '!.git/**' -g '!scripts/security-check.sh' -e '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{25,}|sk-[A-Za-z0-9]{20,}' .; then
    echo 'Possible credential material is tracked.' >&2
    exit 1
fi

echo 'Source-file and credential-pattern checks passed.'
