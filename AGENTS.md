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
og.png                  Open Graph preview image (1200x630)
rss.xml                 RSS 2.0 feed of newest tools (top 50 by `created`)
scripts/categorize.jq   jq script that assigns a category to each repo
scripts/regenerate.sh   refetches all repos and rewrites tools.json (+ rss.xml)
scripts/build-rss.sh    generates rss.xml from tools.json
```

No build step. To preview locally:

```sh
python3 -m http.server 8000
# then open http://localhost:8000/
```

`fetch('tools.json')` does not work from `file://`, so a local server is required.

## `tools.json` schema

Sorted by `(categories[0] asc, stars desc, name asc)`. Each entry:

```json
{
  "name":        "ridgepole",
  "url":         "https://github.com/ridgepole/ridgepole",
  "categories":  ["Database"],
  "language":    "Ruby",
  "languages":   ["Ruby", "Shell"],
  "description": "Manage DB schema with a Ruby DSL",
  "stars":       800,
  "updated":     "2024-01-01",
  "created":     "2014-01-01"
}
```

`language` is GitHub's primary language; `languages` is the top 2 by byte size
(used for card display only — the filter and pie chart still use `language`).

`categories` is an array — a tool can belong to multiple categories.
The **first element is the "primary" category** and decides which section the
card appears in when sorted by category. Filtering matches if **any** category
in the array is selected.

Category names must match one the page knows about. The canonical display
order lives in the `order` array inside `index.html` — if you add a new
category, also add it there so it sorts where you want.

## Updating the data

### Small manual edits

Open `tools.json` and edit the relevant entry. Keep the file sorted afterwards:

```sh
jq 'sort_by(.categories[0], -.stars, .name)' tools.json > tools.json.new && mv tools.json.new tools.json
```

Validate it parses: `jq . tools.json > /dev/null`.

After editing `tools.json`, rebuild the RSS feed:

```sh
./scripts/build-rss.sh
```

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
- name does **not** end with `.github.io` (these are GitHub Pages sites, including this one)
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

If you want to override or add categories without changing the heuristic, just
edit `categories` in `tools.json` directly (e.g. `["AWS", "CLI"]`). The next
`regenerate.sh` run will overwrite that, so for sticky overrides change
`categorize.jq` instead.

## Page conventions

- **UI text is English.** Descriptions can stay in whatever language GitHub returns.
- **Language colors** mirror GitHub linguist (`langColors` object in `index.html`).
  Add new languages there if a new primary language appears.
- **Filter state is in `location.hash`** (e.g. `#q=foo&cat=AWS,Terraform&lang=Go&sort=newest`).
  Don't break that contract — links may be shared.
- **No external dependencies / no build.** Keep it that way; the whole point is a
  zero-friction static page.

## Deploying

GitHub Pages is built via `.github/workflows/pages.yml` (Pages source must be set
to "GitHub Actions" in repo settings). The workflow rewrites `?v=DEV` in
`index.html` to `?v=<short-sha>` before publishing, so a new commit busts the
CSS cache automatically. Just `git push` — the action rebuilds within ~1 minute.

Local dev still works fine: `style.css?v=DEV` resolves to the same file when
served from `python3 -m http.server`.

Status:

```sh
gh api repos/winebarrel/winebarrel.github.io/pages --jq '.status'
```
