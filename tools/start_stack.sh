#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f lobby/.env ]]; then
  echo "Copy lobby/.env.example to lobby/.env and fill secrets first." >&2
  exit 1
fi
mkdir -p lobby/ops-data export
docker compose up -d
echo "Stack up. Check: curl -s http://127.0.0.1:8080/v1/health"
