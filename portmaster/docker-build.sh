#!/usr/bin/env bash
# Convenience wrapper: builds the Docker image (using cache) then runs
# the cross-compile container to produce dist/3sx.zip.
#
# Usage:
#   bash portmaster/docker-build.sh           # build only
#   bash portmaster/docker-build.sh --verify  # build + run verify.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="3sx-portmaster"
DO_VERIFY=""

for arg in "$@"; do
    case "$arg" in
        --verify) DO_VERIFY="--verify" ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

echo "==> Building Docker image: $IMAGE"
docker build -t "$IMAGE" -f "$REPO_ROOT/portmaster/Dockerfile" "$REPO_ROOT"

echo "==> Running cross-compile container"
docker run --rm \
    -v "$REPO_ROOT:/src" \
    "$IMAGE" \
    /src/portmaster/build.sh $DO_VERIFY

echo "==> Output: $REPO_ROOT/dist/3sx.zip"
