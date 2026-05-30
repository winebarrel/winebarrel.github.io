#!/bin/sh
# Regenerate tools.json from the three GitHub accounts.
# Requires: gh, jq

set -eu

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
script_dir="$repo_dir/scripts"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fields='name,description,primaryLanguage,repositoryTopics,stargazerCount,pushedAt,createdAt,url,isFork'

echo "fetching repos…"
gh repo list winebarrel --limit 500 --no-archived --source --json "$fields" > "$tmp/winebarrel.json"
gh repo list ridgepole  --limit 100 --no-archived          --json "$fields" > "$tmp/ridgepole.json"
gh repo list quetarohq  --limit 100 --no-archived          --json "$fields" > "$tmp/quetarohq.json"

echo "categorizing…"
jq -s 'add' "$tmp/winebarrel.json" "$tmp/ridgepole.json" "$tmp/quetarohq.json" \
  | jq -f "$script_dir/categorize.jq" \
  | jq '[.[] | select(.include) | {name, url, categories, language, description, stars, updated, created}]
        | sort_by(.categories[0], -.stars, .name)' \
  > "$repo_dir/tools.json"

echo "tools.json entries: $(jq 'length' "$repo_dir/tools.json")"
