#!/usr/bin/env bash
set -euo pipefail
rc=0
for f in */docker-compose.yml; do
    d=$(dirname "$f")
    envf=/dev/null
    [ -f "$d/.env.example" ] && envf="$d/.env.example"
    if docker compose --env-file "$envf" -f "$f" config -q 2>/tmp/err; then
        echo "OK $f"
    else
        echo "::error file=$f::compose tidak valid: $(cat /tmp/err)"; rc=1
    fi
done
exit $rc