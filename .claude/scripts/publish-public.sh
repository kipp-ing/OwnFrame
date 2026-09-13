#!/usr/bin/env bash
# Publishes a marketing/App-Store-free mirror of local `main` to the public
# GitHub repo (remote `public`). Filters a scratch clone with git-filter-repo
# and force-pushes it — never touches this working repo or its `origin`
# (the private full-history backup). Re-run whenever main has new source
# commits worth publishing; every run rewrites the public repo's history.
set -euo pipefail

REPO_DIR="$(git rev-parse --show-toplevel)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# Keep in sync with the list in CLAUDE.md under "Public mirror".
EXCLUDE_PATHS=(
  "Design/AppStore"
  "Design/Reference"
  "docs/design"
  "docs/app-store-listing.md"
  "docs/store-story.md"
  "docs/where-the-money-goes.md"
  "docs/handover-store-slots.md"
  "docs/release-1.1-handout.md"
  "docs/presentation-overhaul-plan.md"
  "specs/9010-store-presentation"
)

git clone --no-local "$REPO_DIR" "$SCRATCH/export"
cd "$SCRATCH/export"

filter_args=()
for p in "${EXCLUDE_PATHS[@]}"; do
  filter_args+=(--path "$p")
done
git filter-repo "${filter_args[@]}" --invert-paths

echo "Checking for dangling references to excluded paths..."
if grep -rnF -f <(printf '%s\n' "${EXCLUDE_PATHS[@]}") . --include='*.md'; then
  echo "WARNING: lines above still mention an excluded path — check for dead links before publishing." >&2
fi

public_url="$(git -C "$REPO_DIR" remote get-url public)"
git remote add public-origin "$public_url"
git push public-origin main:main --force

echo "Published to $public_url (history rewritten)."
