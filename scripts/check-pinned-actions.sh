#!/usr/bin/env bash
set -euo pipefail
bad=$(grep -rnE '^\s*-?\s*uses:\s*[^.[:space:]]' .github/workflows \
    | grep -vE '@[0-9a-f]{40}(\s|$)' || true)
if [ -n "$bad" ]; then
    echo "::error::Action belum dipin ke SHA 40 karakter:"
    echo "$bad"
    exit 1
fi
echo "OK: semua actttion dipin ke SHA"