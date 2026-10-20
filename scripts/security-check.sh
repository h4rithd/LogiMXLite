#!/bin/bash
# Fast, dependency-free checks for accidental private files and common credential formats.
set -euo pipefail
cd "$(dirname "$0")/.."

if git ls-files -z | tr '\0' '\n' | grep -Ei '(^|/)(settings\.db|settings\.json|backup\.json|\.env([.]|$)|[^/]+\.(p8|p12|pem|key|mobileprovision)|LogiMXLite_(Codex_Build_Prompt|Configuration_Analysis|sanitized_reference)\.[^/]+|reference\.json)$'; then
    echo 'Private or generated files are tracked.' >&2
    exit 1
fi

if git grep -I -l -E -- '-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{25,}|sk-[A-Za-z0-9]{20,}' -- ':!scripts/security-check.sh'; then
    echo 'Possible credential material is tracked.' >&2
    exit 1
fi

echo 'Tracked-file and credential-pattern checks passed.'
