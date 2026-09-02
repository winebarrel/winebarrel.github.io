#!/bin/bash
# Sync the `pinned` flag in tools.json with the Pinned section of the GitHub
# profiles (winebarrel, ridgepole, quetarohq). Run on its own to refresh pins
# without a full regenerate; regenerate.sh also calls it.
# Requires: gh (authenticated), jq

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Pinned items are only exposed through the GraphQL API. `repositoryOwner`
# covers both users and organizations; the ProfileOwner spread is what carries
# `pinnedItems` for either kind.
query='
query {
  winebarrel: repositoryOwner(login: "winebarrel") { ...pins }
  ridgepole:  repositoryOwner(login: "ridgepole")  { ...pins }
  quetarohq:  repositoryOwner(login: "quetarohq")  { ...pins }
}
fragment pins on RepositoryOwner {
  ... on ProfileOwner {
    pinnedItems(first: 6, types: REPOSITORY) {
      nodes { ... on Repository { url } }
    }
  }
}'

echo "fetching pinned repos…"
gh api graphql -f query="$query" \
  | jq '[.data[] | .pinnedItems.nodes[]?.url]' \
  > "$tmp/pinned.json"

echo "pinned: $(jq -r 'join(", ")' "$tmp/pinned.json")"

jq --slurpfile p "$tmp/pinned.json" '
  ($p[0]) as $pinned |
  map(.pinned = (.url as $u | ($pinned | index($u)) != null))
' "$repo_dir/tools.json" > "$tmp/tools.json"
mv "$tmp/tools.json" "$repo_dir/tools.json"

missing=$(jq -r --slurpfile p "$tmp/pinned.json" '
  [.[].url] as $have | $p[0][] | . as $u | select(($have | index($u)) == null)
' "$repo_dir/tools.json")
if [ -n "$missing" ]; then
  echo "warning: pinned on GitHub but not in tools.json (excluded by the include filter?):" >&2
  printf '  %s\n' $missing >&2
fi
