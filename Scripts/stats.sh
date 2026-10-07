#!/bin/bash
# Who has actually downloaded it, and where they came from.
#
#   Scripts/stats.sh
#
# Two numbers are easy to misread, so they are labelled here rather than
# left to flatter: clone counts are dominated by bots that pull every newly
# public repository, and downloads include your own verification runs.

set -euo pipefail
REPO="trustbe/nativevoice"

echo "▸ releases"
gh api "repos/$REPO/releases" --jq '
  .[] | select(.assets | length > 0) |
  "   \(.tag_name)  \(.published_at[0:10])  " +
  ([.assets[] | "\(.name | split("-") | last) \(.download_count)×"] | join("  "))'

TOTAL=$(gh api "repos/$REPO/releases" --jq '[.[].assets[].download_count] | add // 0')
echo "   ────────────────────────────────"
printf "   %s downloads in total\n\n" "$TOTAL"

echo "▸ interest"
gh api "repos/$REPO" --jq '
  "   stars \(.stargazers_count)   watchers \(.subscribers_count)   forks \(.forks_count)   open issues \(.open_issues_count)"'
gh api "repos/$REPO/traffic/views" --jq '
  "   views \(.count) from \(.uniques) unique visitors (14 days)"'
# Clones are listed last and labelled, because the number is large and means
# very little: most of it is automated mirroring of new public repositories.
gh api "repos/$REPO/traffic/clones" --jq '
  "   clones \(.count) from \(.uniques) sources — mostly bots, not readers"'

echo
echo "▸ where people came from"
gh api "repos/$REPO/traffic/popular/referrers" --jq '
  if length == 0 then "   nowhere yet — nothing links here"
  else (.[] | "   \(.referrer)  \(.count) views, \(.uniques) unique") end'
