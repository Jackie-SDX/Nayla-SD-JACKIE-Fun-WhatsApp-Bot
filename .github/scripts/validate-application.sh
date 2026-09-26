#!/usr/bin/env bash
set -euo pipefail
git diff --check
if [[ -n "${INITIAL_SHA:-}" ]]; then git diff --check "$INITIAL_SHA"; fi
jq empty opencode.json
jq empty Nayla/package.json
ruby -e 'require "yaml"; Dir[".github/workflows/*.yml", ".github/dependabot.yml"].uniq.each { |f| YAML.load_file(f); puts "YAML OK: #{f}" }'
while IFS= read -r -d '' f; do node --check "$f"; done < <(git ls-files -z -- '*.js' '*.cjs' '*.mjs')
npm --prefix Nayla test
git diff --stat ${INITIAL_SHA:+"$INITIAL_SHA"} 2>/dev/null || git diff --stat || true
git status --short
echo 'Application/config deterministic validation: PASS'
