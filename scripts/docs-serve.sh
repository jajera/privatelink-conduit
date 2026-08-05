#!/usr/bin/env bash
# Preview the docs site locally.
# Prefers Docker (no Ruby install). Falls back to host Bundler if present.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="http://127.0.0.1:4000/privatelink-conduit/"

if command -v docker >/dev/null 2>&1; then
  echo "Starting docs with Docker Compose..."
  echo "Open ${URL}"
  cd "$ROOT"
  exec docker compose -f docs/docker-compose.yml up "$@"
fi

if command -v bundle >/dev/null 2>&1; then
  echo "Starting docs with host Bundler..."
  cd "$ROOT/docs"
  bundle check >/dev/null 2>&1 || bundle install
  echo "Open ${URL}"
  exec bundle exec jekyll serve --livereload --watch
fi

echo "Need Docker or Ruby+Bundler to preview docs." >&2
echo "  Docker:  ./scripts/docs-serve.sh" >&2
echo "  Ruby:    cd docs && bundle install && bundle exec jekyll serve" >&2
exit 1
