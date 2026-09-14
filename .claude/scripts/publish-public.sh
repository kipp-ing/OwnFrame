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
  "docs/design/appstore prerenders"
  "docs/design/scene-brief.md"
  "docs/app-store-listing.md"
  "docs/store-story.md"
  "docs/where-the-money-goes.md"
  "docs/handover-store-slots.md"
  "docs/release-1.1-handout.md"
  "docs/presentation-overhaul-plan.md"
  "docs/hitl.md"
  "docs/hitl-session-guide.md"
  "specs/9010-store-presentation"
)

git clone --no-local "$REPO_DIR" "$SCRATCH/export"
cd "$SCRATCH/export"

filter_args=()
for p in "${EXCLUDE_PATHS[@]}"; do
  filter_args+=(--path "$p")
done
git filter-repo "${filter_args[@]}" --invert-paths

# Mirror-only fix: local main's links to the excluded paths are valid there
# (the files exist locally), but dangling once those paths are filtered out.
# De-link them here rather than in local main, where they're correct as-is.
python3 - <<'PY'
path = "specs/9000-design-language/spec.md"
s = open(path).read()
s = s.replace(
    "Work-package narrative:\n[`docs/presentation-overhaul-plan.md`](../../docs/presentation-overhaul-plan.md) (AP-U, AP-0).\nDirectional input, explicitly **not** a target:\n[`Design/Reference/README.md`](../../Design/Reference/README.md).",
    "Work-package narrative and directional input (AP-U, AP-0) live in the private App Store/marketing\nmirror, not this repo."
)
s = s.replace(
    "- **FR-9000-36**: Store copy is governed by this spec through its sub-spec\n  [`9010-store-presentation`](../9010-store-presentation/spec.md). A term retired here is retired in\n  the listing; a term introduced in the listing MUST exist in the app.",
    "- **FR-9000-36**: Store copy is governed by this spec through its sub-spec `9010-store-presentation`\n  (kept in the private App Store/marketing mirror, not this repo). A term retired here is retired in\n  the listing; a term introduced in the listing MUST exist in the app."
)
s = s.replace(
    "- **[9010-store-presentation](../9010-store-presentation/spec.md)** — the sub-spec that applies this\n  language to the App Store asset set.",
    "- **9010-store-presentation** — the sub-spec that applies this language to the App Store asset\n  set (private App Store/marketing mirror, not this repo)."
)
open(path, "w").write(s)

path = "docs/spec-overview.md"
lines = open(path).read().split("\n")
lines = [l for l in lines if not l.startswith("| 9010 |")]
open(path, "w").write("\n".join(lines))
PY
git add specs/9000-design-language/spec.md docs/spec-overview.md
if ! git diff --cached --quiet; then
  git commit -q -m "docs: delink specs kept in the private App Store/marketing mirror"
fi

echo "Checking for dangling references to excluded paths..."
if grep -rnF -f <(printf '%s\n' "${EXCLUDE_PATHS[@]}") . --include='*.md'; then
  echo "WARNING: lines above still mention an excluded path — check for dead links before publishing." >&2
fi

public_url="$(git -C "$REPO_DIR" remote get-url public)"
git remote add public-origin "$public_url"
git push public-origin main:main --force

echo "Published to $public_url (history rewritten)."
