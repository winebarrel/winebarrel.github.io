#!/bin/bash
# Generate activity.svg — a "commit address map" of the last 52 weeks,
# built from GitHub's per-repo commit_activity stats.
#
# Only repos touched in the last ~14 months are fetched; everything older has
# no activity in the 52-week window anyway.
#
# Requires: gh, jq, curl, python3, bash, xargs

set -eu

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
script_dir="$repo_dir/scripts"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/act"

# The stats endpoints are computed lazily: a cold repo answers 202 with an
# empty body, so each fetch retries with a backoff.
#
# kanmu/* goes through the unauthenticated REST API — same reason as in
# regenerate.sh, the OAuth token is not SSO-authorized for that org.
fetch_activity() {
  local slug="$1"
  local out="$tmp/act/${slug/\//__}.json"
  local body i

  for i in 1 2 3 4 5; do
    case "$slug" in
      kanmu/*)
        body=$(curl -fsS -H 'Accept: application/vnd.github+json' \
          "https://api.github.com/repos/$slug/stats/commit_activity" 2>/dev/null || true) ;;
      *)
        body=$(gh api "repos/$slug/stats/commit_activity" 2>/dev/null || true) ;;
    esac
    if [ -n "$body" ] && [ "$(printf '%s' "$body" | jq -r 'type' 2>/dev/null)" = "array" ]; then
      printf '%s' "$body" > "$out"
      return 0
    fi
    sleep $((i * 2))
  done

  echo "warning: no commit_activity for $slug" >&2
  echo '[]' > "$out"
}
export -f fetch_activity
export tmp

cutoff="$(python3 -c 'import datetime;print((datetime.date.today()-datetime.timedelta(days=430)).isoformat())')"

echo "fetching commit activity (since $cutoff)…"
jq -r --arg cutoff "$cutoff" \
  '.[] | select(.updated >= $cutoff) | .url | sub("https://github.com/"; "")' \
  "$repo_dir/tools.json" \
  | xargs -P 8 -n 1 -I{} bash -c 'fetch_activity "$@"' _ {}

python3 "$script_dir/activity-svg.py" "$repo_dir/tools.json" "$tmp/act" "$repo_dir/activity.svg"
