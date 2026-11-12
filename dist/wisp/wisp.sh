#!/usr/bin/env bash
# Wisp's day-to-day tasks; see wisp.mk. DRY_RUN=1 prints what sync and
# release would change instead of changing it.
set -euo pipefail

cd "$(dirname "$0")/../.."

REPO=callistobound/wisp
BRANCH=downstream
IDENTITY=${WISP_CODESIGN_IDENTITY:-68235C09FAF010917A7F92C2C44E2ABFC52FAAC8}
APP=zig-out/Wisp.app
DEBUG_ID=com.callistobound.wisp.debug

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Runs a command, or only prints it when DRY_RUN=1.
act() {
  if [ "${DRY_RUN:-}" = 1 ]; then
    printf 'would run: %s\n' "$*"
  else
    "$@"
  fi
}

require_clean_branch() {
  [ "$(git branch --show-current)" = "$BRANCH" ] || die "switch to $BRANCH first"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "commit or stash your changes first"
  fi
}

zon_version() {
  sed -n 's/^ *\.version = "\(.*\)",/\1/p' build.zig.zon | head -1
}

# Newest Ghostty release tag, e.g. v1.4.1.
latest_ghostty_tag() {
  git ls-remote --tags --refs origin 'refs/tags/v*' |
    sed 's|.*refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}

cmd_build() {
  say "Building Wisp (signed)"
  zig build -Dmacos-codesign-identity="$IDENTITY"
}

cmd_run() {
  cmd_build
  say "Restarting $APP"
  osascript -e "tell application id \"$DEBUG_ID\" to quit" 2>/dev/null || true
  for _ in $(seq 1 10); do pgrep -f "$APP/Contents/MacOS/wisp" >/dev/null || break; sleep 1; done
  open "$APP"
}

cmd_test_quick() {
  say "Python tests"
  python3 -m unittest discover -s dist/wisp -p 'test_*.py'
  say "Swift tests"
  (cd macos && xcodebuild test -scheme Ghostty -skip-testing GhosttyUITests -arch arm64 -quiet)
}

cmd_test() {
  cmd_test_quick
  say "Zig tests (slow)"
  zig build test -Demit-macos-app=false
}

cmd_push() {
  say "Pushing $BRANCH"
  act git push wisp "$BRANCH"
  act dist/wisp/disable-upstream-workflows.sh
}

cmd_sync() {
  require_clean_branch
  say "Merging Ghostty main"
  git fetch origin main
  if git merge-base --is-ancestor origin/main HEAD; then
    echo "already up to date with Ghostty main"
    return
  fi
  echo "$(git rev-list --count HEAD..origin/main) new Ghostty commits"
  act git merge --no-edit origin/main
  cmd_push
}

cmd_release() {
  require_clean_branch
  local tag base
  tag=$(latest_ghostty_tag)
  [ -n "$tag" ] || die "no Ghostty release tags found"
  base=${tag#v}
  say "Newest Ghostty release: $tag"

  if ! git merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then
    git fetch origin main "refs/tags/$tag:refs/tags/$tag"
    say "Merging $tag"
    if [ "${DRY_RUN:-}" = 1 ]; then
      echo "would run: git merge --no-edit $tag"
      echo "(the version check below uses the current build.zig.zon)"
    else
      git merge --no-edit "$tag"
    fi
  fi

  git fetch --quiet wisp 'refs/tags/*:refs/tags/*' 2>/dev/null || true
  local n=1
  while git rev-parse -q --verify "refs/tags/v$base-wisp.$n" >/dev/null; do n=$((n + 1)); done
  local release="v$base-wisp.$n"
  python3 dist/wisp/release_version.py "$release" build.zig.zon >/dev/null

  say "Release $release ($base+wisp.$n) from $(git rev-parse --short HEAD)"
  if [ "${DRY_RUN:-}" != 1 ]; then
    read -r -p "Push $BRANCH and tag $release? [y/N] " answer
    [ "$answer" = y ] || die "cancelled"
  fi
  cmd_push
  act git tag -m "Wisp $base+wisp.$n" "$release"
  act git push wisp "$release"
  echo "watch it with: make watch"
}

cmd_status() {
  echo "local:  $(git rev-parse --short HEAD) on $(git branch --show-current), build $(git rev-list --count HEAD), build.zig.zon $(zon_version)"
  echo "behind Ghostty main by $(git rev-list --count HEAD..origin/main 2>/dev/null || echo '?') commits; newest Ghostty release $(latest_ghostty_tag)"
  echo "tip:    $(gh release view tip -R "$REPO" --json body --jq .body 2>/dev/null || echo none)"
  echo "stable: $(gh release view -R "$REPO" --json tagName --jq .tagName 2>/dev/null || echo none)"
  echo "recent runs:"
  gh run list -R "$REPO" --limit 5
}

cmd_docs() {
  local out
  out=$(mktemp -d)
  say "Generating the reference"
  zig build -Demit-webdata -Demit-macos-app=false -p "$out"
  python3 dist/wisp/docs_from_webdata.py "$out/share/ghostty/webdata" dist/wisp/site/src/content/docs
  say "Starting the docs preview"
  cd dist/wisp/site
  [ -d node_modules ] || npm ci
  npm run dev
}

cmd_watch() {
  gh run watch -R "$REPO" "$(gh run list -R "$REPO" --limit 1 --json databaseId --jq '.[0].databaseId')"
}

case "${1:-}" in
  build) cmd_build ;;
  run) cmd_run ;;
  test) cmd_test ;;
  test-quick) cmd_test_quick ;;
  push) cmd_push ;;
  sync) cmd_sync ;;
  release) cmd_release ;;
  status) cmd_status ;;
  docs) cmd_docs ;;
  watch) cmd_watch ;;
  *) die "unknown command: ${1:-} (see 'make help')" ;;
esac
