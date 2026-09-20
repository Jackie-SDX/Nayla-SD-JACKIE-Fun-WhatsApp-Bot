#!/usr/bin/env bash
set -euo pipefail

git diff --check
if [[ -n "${INITIAL_SHA:-}" ]]; then git diff --check "$INITIAL_SHA"; fi

jq empty package.json
jq empty opencode.json

ruby -e 'require "yaml"; Dir[".github/workflows/*.yml", ".github/dependabot.yml"].uniq.each { |f| YAML.load_file(f); puts "YAML OK: #{f}" }'

while IFS= read -r -d '' f; do
  node --check "$f"
done < <(git ls-files -z -- '*.js' '*.cjs' '*.mjs')

if [[ -f scripts/test-simple-web-crawler.js ]]; then
  node scripts/test-simple-web-crawler.js
fi

if jq -e '.scripts.test? and (.scripts.test != null)' package.json >/dev/null; then
  npm test
fi

git diff --stat ${INITIAL_SHA:+"$INITIAL_SHA"} 2>/dev/null || git diff --stat || true
git status --short
echo "Application/config deterministic validation: PASS"
