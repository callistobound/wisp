#!/usr/bin/env bash
# Downloads a release's appcast.xml to OUT, for update_appcast.py to extend.
# A release that doesn't exist yet means a new feed: OUT isn't written and this
# succeeds. Anything else (network, auth, a release without an appcast) fails,
# so a transient error can't reset the feed.
#
# Usage: fetch-appcast.sh REPO TAG|latest OUT
set -euo pipefail

repo=$1 tag=$2 out=$3

if [ "$tag" = latest ]; then
  endpoint="repos/$repo/releases/latest"
else
  endpoint="repos/$repo/releases/tags/$tag"
fi

if ! err=$(gh api "$endpoint" --jq .tag_name 2>&1 >/dev/null); then
  case "$err" in
    *"HTTP 404"*) echo "no $tag release in $repo yet; starting a new feed"; exit 0 ;;
    *) echo "$err" >&2; exit 1 ;;
  esac
fi

release=$(gh api "$endpoint" --jq .tag_name)
gh release download "$release" -R "$repo" -p appcast.xml -O "$out" --clobber
echo "fetched the appcast from $release"
