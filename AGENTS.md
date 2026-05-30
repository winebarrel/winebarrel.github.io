# winebarrel.github.io

A single static page listing tools and libraries from the GitHub accounts
[`winebarrel`](https://github.com/winebarrel), [`ridgepole`](https://github.com/ridgepole),
and [`quetarohq`](https://github.com/quetarohq), grouped by category.

Published at https://winebarrel.github.io/ via GitHub Pages
(repo: `main` branch root → `<user>.github.io` user site).

## Layout

```
index.html              page markup + inline JS that fetches tools.json and renders
style.css               styles (light/dark via prefers-color-scheme)
tools.json              data — array of tool objects, sorted by category then stars
scripts/categorize.jq   jq script that assigns a category to each repo
scripts/regenerate.sh   refetches all repos and rewrites tools.json
```

No build step. To preview locally:

```sh
python3 -m http.server 8000
# then open http://localhost:8000/
```

`fetch('tools.json')` does not work from `file://`, so a local server is required.

## `tools.json` schema

Sorted by `(category asc, stars desc, name asc)`. Each entry:

```json
{
  "name":        "ridgepole",
  "url":         "https://github.com/ridgepole/ridgepole",
  "category":    "Database",
  "language":    "Ruby",
  "description": "Manage DB schema with a Ruby DSL",
  "stars":       800,
  "updated":     "2024-01-01",
  "created":     "2014-01-01"
}
```

`category` must match one of the categories the page knows about. The canonical
display order lives in the `order` array inside `index.html` — if you add a new
category, also add it there so it sorts where you want.

## Updating the data

### Small manual edits

Open `tools.json` and edit the relevant entry. Keep the file sorted afterwards:

```sh
jq 'sort_by(.category, -.stars, .name)' tools.json > tools.json.new && mv tools.json.new tools.json
```

Validate it parses: `jq . tools.json > /dev/null`.

### Refresh from GitHub (bulk)

```sh
./scripts/regenerate.sh
```

This refetches the three accounts (non-archived only), runs `categorize.jq`,
applies the include filter, and overwrites `tools.json`.

Review the diff and re-curate manually before committing — auto-generation
will re-add things you previously removed.

## Filtering rules

`scripts/categorize.jq` sets `include: true/false` per repo. A repo is included
when **all** of these hold:

- not archived (already filtered out by `gh repo list --no-archived`)
- not a fork (filtered by `--source`)
- name does **not** start with `homebrew-` (these are Homebrew tap repos, not tools themselves)
- AND one of:
  - `stargazerCount >= 3`, or
  - has at least one topic, or
  - description longer than 10 chars

Adjust the heuristic in `categorize.jq` if needed.

## Categorization

`categorize.jq` matches against the lowercased `name + description + topics` haystack,
falls back to `primaryLanguage`, and finally puts the repo in `Other`. The match
order matters — earlier branches win. Tweak the regexes there if a repo lands
in the wrong bucket.

If you want to override a category without changing the heuristic, just edit
`category` in `tools.json` directly. The next `regenerate.sh` run will overwrite
that, so for sticky overrides change `categorize.jq` instead.

## Page conventions

- **UI text is English.** Descriptions can stay in whatever language GitHub returns.
- **Language colors** mirror GitHub linguist (`langColors` object in `index.html`).
  Add new languages there if a new primary language appears.
- **Filter state is in `location.hash`** (e.g. `#q=foo&cat=AWS,Terraform&lang=Go&sort=newest`).
  Don't break that contract — links may be shared.
- **No external dependencies / no build.** Keep it that way; the whole point is a
  zero-friction static page.

## Deploying

GitHub Pages serves from `main` root automatically (user site convention). Just
`git push` — the site rebuilds within ~1 minute. Status:

```sh
gh api repos/winebarrel/winebarrel.github.io/pages --jq '.status'
```
