#!/bin/bash
# Regenerate tools.json from the three GitHub accounts.
# Requires: gh, jq, bash, xargs

set -eu

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
script_dir="$repo_dir/scripts"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fields='name,description,primaryLanguage,languages,repositoryTopics,stargazerCount,pushedAt,createdAt,url,isFork'

echo "fetching repos…"
gh repo list winebarrel --limit 500 --no-archived --source --json "$fields" > "$tmp/winebarrel.json"
gh repo list ridgepole  --limit 100 --no-archived          --json "$fields" > "$tmp/ridgepole.json"
gh repo list quetarohq  --limit 100 --no-archived          --json "$fields" > "$tmp/quetarohq.json"

# Override `createdAt` with the actual first-commit date on the default
# branch (GitHub's createdAt is when the repo was created; imported repos
# can have older commits).
fetch_first_commit() {
  local repo="$1"
  local headers last d
  headers=$(gh api "repos/$repo/commits?per_page=1" --include 2>/dev/null | head -50 || true)
  last=$(printf '%s\n' "$headers" | grep -i '^link:' | grep -oE 'page=[0-9]+>; rel="last"' | head -1 | grep -oE '[0-9]+' || true)
  [ -z "$last" ] && last=1
  d=$(gh api "repos/$repo/commits?per_page=1&page=$last" --jq '.[0].commit.committer.date' 2>/dev/null | cut -c1-10 || true)
  printf '%s\t%s\n' "$repo" "$d"
}
export -f fetch_first_commit

echo "fetching first-commit dates (parallel)…"
jq -r '.[] | .url | sub("https://github.com/"; "")' \
  "$tmp/winebarrel.json" "$tmp/ridgepole.json" "$tmp/quetarohq.json" \
  | xargs -P 8 -n 1 -I{} bash -c 'fetch_first_commit "$@"' _ {} \
  > "$tmp/firstcommits.tsv"

jq -Rsc '
  [ split("\n") | .[] | select(length > 0) | split("\t")
    | select(length == 2 and (.[1] | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")))
    | {key: .[0], value: .[1]} ]
  | from_entries
' "$tmp/firstcommits.tsv" > "$tmp/firstcommits.json"

echo "categorizing…"
jq -s 'add' "$tmp/winebarrel.json" "$tmp/ridgepole.json" "$tmp/quetarohq.json" \
  | jq --slurpfile fcs "$tmp/firstcommits.json" '
      ($fcs[0]) as $m |
      map(. + {createdAt: ($m[.url | sub("https://github.com/"; "")] // (.createdAt | .[0:10]))})
    ' \
  | jq -f "$script_dir/categorize.jq" \
  | jq '[.[] | select(.include) | {name, url, categories, language, languages, description, stars, updated, created}]
        | sort_by(.categories[0], -.stars, .name)' \
  > "$repo_dir/tools.json"

echo "tools.json entries: $(jq 'length' "$repo_dir/tools.json")"

echo "building rss.xml…"
"$script_dir/build-rss.sh"
