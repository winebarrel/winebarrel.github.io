# winebarrel.github.io

A single static page listing tools and libraries from the GitHub accounts
[`winebarrel`](https://github.com/winebarrel), [`ridgepole`](https://github.com/ridgepole),
and [`quetarohq`](https://github.com/quetarohq), plus a handful of named repos
from [`kanmu`](https://github.com/kanmu), grouped by category.

Published at https://winebarrel.github.io/ via GitHub Pages
(repo: `main` branch root → `<user>.github.io` user site).

## Layout

```
index.html              page markup + inline JS that fetches tools.json and renders
style.css               styles (light/dark via prefers-color-scheme)
tools.json              data — array of tool objects, sorted by category then stars
og.png                  Open Graph preview image (1200x630)
rss.xml                 RSS 2.0 feed of newest tools (top 50 by `created`)
activity.svg            commit address map of the last 52 weeks (see below)
scripts/categorize.jq   jq script that assigns a category to each repo
scripts/regenerate.sh   refetches all repos and rewrites tools.json (+ pins, rss.xml, activity.svg)
scripts/sync-pinned.sh  syncs the `pinned` flag with the GitHub profiles' Pinned section
scripts/build-rss.sh    generates rss.xml from tools.json
scripts/build-activity.sh  fetches commit stats and generates activity.svg
scripts/activity-svg.py    renders the SVG (stdlib only, called by build-activity.sh)
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
  "created":     "2014-01-01",
  "archived":    false,
  "pinned":      false
}
```

`language` is GitHub's primary language; `languages` is the top 2 by byte size
(used for card display only — the filter and pie chart still use `language`).

`archived` mirrors GitHub's archived flag. Archived repos stay in `tools.json`
and get an "Archived" badge on the card, but the page hides them by default —
the "Hide archived" checkbox is on unless `#archived=1` is in the URL. Chip
counts, the pie charts and the `n / m` tally all follow that setting.

`pinned` mirrors the Pinned section of the GitHub profiles (winebarrel,
ridgepole, quetarohq). Pinned tools get a 📌 badge on the card and are
repeated in a "Pinned" section at the top of the list, above whatever sort
is active. The section follows the current filters (search, category,
language, archived) and sorts by stars. To change what is pinned, pin or
unpin the repo on GitHub and run `./scripts/sync-pinned.sh` (see below);
`regenerate.sh` runs the same sync. Only repos that pass the include filter
can show up — the sync warns about pinned repos that aren't in `tools.json`.

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

### Sync pins from GitHub

```sh
./scripts/sync-pinned.sh
```

Fetches the Pinned section of the three profiles (GraphQL, needs an
authenticated `gh`) and rewrites the `pinned` flag in `tools.json` in place.
Nothing else is touched, so this is safe to run on its own.

### Refresh from GitHub (bulk)

```sh
./scripts/regenerate.sh
```

This refetches the three accounts (archived included, forks excluded) plus the
repos named in `kanmu_repos`, runs `categorize.jq`, applies the include filter,
overwrites `tools.json`, and then runs the pin sync, the RSS build, and the
activity map build.

The `kanmu` repos are fetched through the **unauthenticated** REST API and
reshaped into the same schema — the OAuth token `gh` uses is not SSO-authorized
for that org, so an authenticated call returns 403. Same trick in
`build-activity.sh`.

Review the diff and re-curate manually before committing — auto-generation
will re-add things you previously removed.

## Activity map (`activity.svg`)

```sh
./scripts/build-activity.sh
```

Fetches `/stats/commit_activity` for every repo in `tools.json` touched in the
last ~430 days and renders `activity.svg`, shown on the page inside a collapsed
`<details>` in the `#stats` section (`figure.stats-wide`, after the
"Created per month" bars). It is a plain `<img>`, so it themes itself through
`prefers-color-scheme` inside the SVG rather than through the page's CSS
variables — keep the tokens in `activity-svg.py` (`LIGHT` / `DARK`) in sync
with `style.css` if the palette changes.

The whole 52-week history is flattened into one address space and wrapped at
96 columns: one square = one commit, read left→right / top→bottom, oldest
first. Within each month the commits are grouped per product, so each product
gets one contiguous block sized by how much it was worked on that month.
Hue = category, shade = product within that category, stepped rules = month
boundaries.

Category → hue is a **fixed** mapping in `CATS` at the top of
`activity-svg.py`; categories not listed there fall into the gray "Other"
slot. Add a new category there (and keep the order) rather than letting the
colours follow whatever ranks highest that month.

The stats endpoints are computed lazily by GitHub — a cold repo answers `202`
with an empty body, so the fetch retries with a backoff. A repo that never
answers is warned about on stderr and treated as having no activity.

## Filtering rules

`scripts/categorize.jq` sets `include: true/false` per repo. A repo is included
when **all** of these hold:

- not a fork (filtered by `--source`)
- name is not in the manual exclusion list at the top of the `include` expression
- name does **not** start with `homebrew-` (these are Homebrew tap repos, not tools themselves)
- name does **not** end with `.github.io` (these are GitHub Pages sites, including this one)
- name does **not** contain `example` (case-insensitive — these are demo/sample repos)
- AND one of:
  - `stargazerCount >= 3`, or
  - has at least one topic, or
  - description longer than 10 chars

Archived repos are **not** filtered out — they are flagged instead (see
`archived` above). Adjust the heuristic in `categorize.jq` if needed.

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
- **Filter state is in `location.hash`** (e.g. `#q=foo&cat=AWS,Terraform&lang=Go&sort=newest&archived=1`).
  Don't break that contract — links may be shared.
- **No external dependencies / no build.** Keep it that way; the whole point is a
  zero-friction static page.

## Deploying

**Commit and push directly to `main`.** Don't open a feature branch or a pull
request for routine changes (data edits, categorization fixes, style tweaks) —
`main` is what GitHub Pages publishes, so anything on a branch is invisible
until it lands there.

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
