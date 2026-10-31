#!/usr/bin/env bash
set -euo pipefail
rc=0

# 1. Hanya nginx yang boleh memetakan port ke host
for f in */docker-compose.yml; do
  [ "$(dirname "$f")" = "nginx" ] && continue
  if grep -nE '^\s*ports:' "$f"; then
    echo "::error file=$f::ports: dilarang, pakai expose + reverse-proxy"; rc=1
  fi
done

# 2. privileged dilarang
if grep -rnE 'privileged:\s*true' --include=docker-compose.yml . ; then
  echo "::error::privileged: true dilarang"; rc=1
fi

# 3. docker.sock hanya untuk monitoring dan devops-lab (watchtower)
if grep -rn '/var/run/docker.sock' --include=docker-compose.yml . \
   | grep -vE '^\./(monitoring|devops-lab)/'; then
  echo "::error::docker.sock hanya boleh di monitoring/ dan devops-lab/"; rc=1
fi

# 4. Backend wajib memakai homelab-network eksternal
for f in */docker-compose.yml; do
  [ "$(dirname "$f")" = "cloudflared" ] && continue
  grep -q 'homelab-network' "$f" || { echo "::warning file=$f::tidak memakai homelab-network"; }
done

exit $rc