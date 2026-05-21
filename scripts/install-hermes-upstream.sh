#!/usr/bin/env bash
# Clone or update the upstream Hermes Agent source tree at a pinned ref.
# Intended to run on the VM, alongside the compose stack at /opt/hermes/stack.
# Produces /opt/hermes/hermes-upstream as the build context for the compose
# service `hermes` and `dashboard`.
set -euo pipefail

REF="${HERMES_REF:-v2026.5.16}"
TARGET="${TARGET:-/opt/hermes/hermes-upstream}"
REPO="https://github.com/NousResearch/hermes-agent.git"

if [ -d "$TARGET/.git" ]; then
  echo "[hermes-upstream] updating existing checkout at $TARGET to $REF"
  git -C "$TARGET" fetch --depth 1 origin "tag" "$REF" --no-tags
  git -C "$TARGET" checkout -f -B "pinned-$REF" "$REF"
else
  echo "[hermes-upstream] cloning $REPO @ $REF -> $TARGET"
  mkdir -p "$(dirname "$TARGET")"
  git clone --depth 1 --branch "$REF" "$REPO" "$TARGET"
fi

echo "[hermes-upstream] HEAD: $(git -C "$TARGET" rev-parse --short HEAD)"
