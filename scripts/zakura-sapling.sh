#!/usr/bin/env bash
#
# Regenerate the local `zakura-sapling` branch.
#
# Zakura (https://github.com/zakura-core/common) is a monorepo with no shared
# git history with zcash/sapling-crypto. It carries a fork of the sapling-crypto
# crate that was imported from zcash/sapling-crypto 0.7.0. This script extracts
# zakura's sapling-crypto history, rewrites it so the crate sits at the repo
# root, and grafts it onto the upstream 0.7.0 commit so the two histories join
# up.
#
# Usage: scripts/zakura-sapling.sh [zakura-rev] [branch]
#   zakura-rev  revision of the zakura monorepo to extract
#               (default: the pinned rev below)
#   branch      branch to (force-)create in this repo (default: zakura-sapling)
#
set -euo pipefail

# --- Hardcoded anchors -------------------------------------------------------

# FORK_BASE: zcash/sapling-crypto commit "Release sapling-crypto version 0.7.0".
# Zakura's sapling-crypto crate was forked from this tree (see the "Record of
# Fork" in its CHANGELOG.md), so the rewritten zakura history is grafted on top
# of it. It is upstream history and is never rewritten.
FORK_BASE=8186b407b47b595a2ea4f04c73d59fdd83bd401f

# IMPORT_COMMIT: zakura's "feat: fork the full crypto closure; wire members with
# path deps instead of patch", which vendored the 0.7.0 tree at
# sapling-crypto/. Every earlier monorepo commit leaves the crate paths
# untouched and is pruned, so after filtering this is the oldest surviving
# commit; its parent is rewritten to FORK_BASE to bake the graft into real
# commit objects.
IMPORT_COMMIT=a57d014096a67071a2c6522a160c7e0dfbeff0f4

# MOVE_COMMIT: zakura's "Move all workspace crates into crates/", a pure rename
# (sapling-crypto/ -> crates/sapling-crypto/). Both path prefixes are rewritten
# to the repo root, so this commit is content-neutral; its file changes are
# cleared so that filter-repo prunes it as empty. (Left alone, the delete-side
# and add-side of the rename collide on the same post-rename pathnames.)
MOVE_COMMIT=4279c920b7a9c35ff87537270103b173492802fa

# PINNED_REV: the zakura-core/common revision `main` depends on. Regenerating
# at any other rev produces a branch that disagrees with the manifest pins.
PINNED_REV=66ddff6adf11ee134efef0e3e28ac5f72ea92824

# Path prefixes the sapling-crypto crate has lived at inside the monorepo.
OLD_CRATE_PATH=sapling-crypto
NEW_CRATE_PATH=crates/sapling-crypto

# --- Arguments ---------------------------------------------------------------

ZAKURA_REV="${1:-$PINNED_REV}"
BRANCH="${2:-zakura-sapling}"

# Work from the repo root regardless of the caller's cwd.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
cd "$REPO"

command -v git-filter-repo >/dev/null 2>&1 || {
  echo "error: git-filter-repo is not installed" >&2
  exit 1
}

ZAKURA_SHA="$(git rev-parse --verify "${ZAKURA_REV}^{commit}")" || {
  echo "error: ${ZAKURA_REV} not found; fetch the zakura remote first" >&2
  exit 1
}
for anchor in "$FORK_BASE" "$IMPORT_COMMIT"; do
  git cat-file -e "${anchor}^{commit}" 2>/dev/null || {
    echo "error: anchor commit ${anchor} not found in $REPO" >&2
    exit 1
  }
done
git merge-base --is-ancestor "$IMPORT_COMMIT" "$ZAKURA_SHA" || {
  echo "error: ${ZAKURA_REV} does not contain the import commit ${IMPORT_COMMIT}" >&2
  exit 1
}

# Which prefix holds the crate at ZAKURA_REV (used only for the tree check).
if git cat-file -e "${ZAKURA_SHA}:${NEW_CRATE_PATH}" 2>/dev/null; then
  CRATE_PATH="$NEW_CRATE_PATH"
elif git cat-file -e "${ZAKURA_SHA}:${OLD_CRATE_PATH}" 2>/dev/null; then
  CRATE_PATH="$OLD_CRATE_PATH"
else
  echo "error: no sapling-crypto crate found in ${ZAKURA_REV}" >&2
  exit 1
fi

# --- Filter in a throwaway clone --------------------------------------------

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zakura-sapling.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

MIRROR="$WORK/mirror"
git clone --no-hardlinks --mirror --quiet "file://$REPO" "$MIRROR"

git -C "$MIRROR" update-ref refs/heads/zakura-src "$ZAKURA_SHA"

# --refs limits the rewrite to the zakura line: upstream commits (FORK_BASE and
# its ancestors) are only referenced as a parent, never rewritten.
git -C "$MIRROR" filter-repo \
  --force \
  --refs refs/heads/zakura-src \
  --replace-refs delete-no-add \
  --path "$OLD_CRATE_PATH" \
  --path "$NEW_CRATE_PATH" \
  --path-rename "${OLD_CRATE_PATH}/:" \
  --path-rename "${NEW_CRATE_PATH}/:" \
  --commit-callback "
if commit.original_id == b'${MOVE_COMMIT}':
    commit.file_changes = []
elif commit.original_id == b'${IMPORT_COMMIT}':
    # Oldest surviving commit: its file changes add the whole crate against an
    # empty tree, so once it gains a parent we must clear the inherited tree
    # (e.g. upstream files the vendored copy does not carry).
    commit.file_changes.insert(0, FileChange(b'DELETEALL'))
    commit.parents = [b'${FORK_BASE}']
"

# --- Publish -----------------------------------------------------------------

git fetch --no-tags --quiet --force "$MIRROR" "refs/heads/zakura-src:refs/heads/${BRANCH}"

# --- Verify ------------------------------------------------------------------

TIP="$(git rev-parse --verify "refs/heads/${BRANCH}")"

MERGE_BASE="$(git merge-base "$TIP" "$FORK_BASE")"
if [ "$MERGE_BASE" != "$FORK_BASE" ]; then
  echo "error: merge-base ${BRANCH} ${FORK_BASE} = ${MERGE_BASE}, expected ${FORK_BASE}" >&2
  exit 1
fi

if ! git diff --quiet "${ZAKURA_SHA}:${CRATE_PATH}" "$TIP"; then
  echo "error: tree of ${BRANCH} differs from ${ZAKURA_REV}:${CRATE_PATH}" >&2
  git --no-pager diff --stat "${ZAKURA_SHA}:${CRATE_PATH}" "$TIP" >&2
  exit 1
fi

COUNT="$(git rev-list --count "${FORK_BASE}..${TIP}")"

echo "${BRANCH} = $(git rev-parse --short "$TIP"), ${COUNT} commits over $(git rev-parse --short "$FORK_BASE"), tree matches ${ZAKURA_REV}"
