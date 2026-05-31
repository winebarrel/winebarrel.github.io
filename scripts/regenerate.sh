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

# Specific repos from the kanmu org (not the whole org).
# Use unauthenticated REST API to bypass the org's SAML enforcement on
# the OAuth token, and reshape into the same schema as `gh repo list`.
kanmu_repos="ddcat rdsauth demitas2 jhol dbtyp pperr"
: > "$tmp/kanmu.ndjson"
for r in $kanmu_repos; do
  repo_json=$(curl -fsS -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/kanmu/$r")
  langs_json=$(curl -fsS -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/kanmu/$r/languages")
  jq -nc --argjson repo "$repo_json" --argjson langs "$langs_json" '
    $repo | {
      name,
      description,
      primaryLanguage: (if .language then {name: .language} else null end),
      languages: ($langs | to_entries | map({node: {name: .key}, size: .value})),
      repositoryTopics: ((.topics // []) | map({name: .})),
      stargazerCount: .stargazers_count,
      pushedAt: .pushed_at,
      createdAt: .created_at,
      url: .html_url,
      isFork: .fork
    }
  ' >> "$tmp/kanmu.ndjson"
done
jq -s '.' "$tmp/kanmu.ndjson" > "$tmp/kanmu.json"

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
  "$tmp/winebarrel.json" "$tmp/ridgepole.json" "$tmp/quetarohq.json" "$tmp/kanmu.json" \
  | xargs -P 8 -n 1 -I{} bash -c 'fetch_first_commit "$@"' _ {} \
  > "$tmp/firstcommits.tsv"

jq -Rsc '
  [ split("\n") | .[] | select(length > 0) | split("\t")
    | select(length == 2 and (.[1] | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")))
    | {key: .[0], value: .[1]} ]
  | from_entries
' "$tmp/firstcommits.tsv" > "$tmp/firstcommits.json"

echo "categorizing…"
jq -s 'add' "$tmp/winebarrel.json" "$tmp/ridgepole.json" "$tmp/quetarohq.json" "$tmp/kanmu.json" \
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
