#!/bin/sh
# Generate rss.xml from tools.json (newest tools by `created` date, top 50).
# Requires: jq

set -eu
export LC_ALL=C

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_date="$(date -u +'%a, %d %b %Y %H:%M:%S GMT')"

jq -r --arg build_date "$build_date" '
  def xml_escape: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\""; "&quot;");
  def rfc822: (. + "T00:00:00Z") | fromdateiso8601 | strftime("%a, %d %b %Y %H:%M:%S GMT");

  ([
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">",
    "<channel>",
    "<title>winebarrel'\''s tools</title>",
    "<link>https://winebarrel.github.io/</link>",
    "<description>Tools and libraries by @winebarrel, @ridgepole, and @quetarohq.</description>",
    "<language>en</language>",
    "<atom:link href=\"https://winebarrel.github.io/rss.xml\" rel=\"self\" type=\"application/rss+xml\"/>",
    "<lastBuildDate>\($build_date)</lastBuildDate>"
  ] | join("\n"))
  + "\n"
  + (sort_by(.created) | reverse | .[0:50] | map(
      "<item>\n"
      + "  <title>\(.name | xml_escape)</title>\n"
      + "  <link>\(.url | xml_escape)</link>\n"
      + "  <guid isPermaLink=\"true\">\(.url | xml_escape)</guid>\n"
      + "  <pubDate>\(.created | rfc822)</pubDate>\n"
      + "  <description>\((.description // "") | xml_escape)</description>\n"
      + ((.categories // []) | map("  <category>\(. | xml_escape)</category>") | join("\n"))
      + (if (.categories // []) | length > 0 then "\n" else "" end)
      + "</item>"
    ) | join("\n"))
  + "\n</channel>\n</rss>\n"
' "$repo_dir/tools.json" > "$repo_dir/rss.xml"

echo "rss.xml items: $(grep -c '<item>' "$repo_dir/rss.xml")"
