#!/bin/bash
# Post-build image verification driver.
#
# Resolves the requested bake targets, works out which tag each one produces,
# and runs verify-image.sh against it. The checks live in verify-image.sh; this
# file only does the wiring.
#
# Run via `task verify` (which builds with --load first), or directly:
#   ./verify.sh           # both variants
#   ./verify.sh alpine    # a single target
#
# Images must already be loaded into the local docker daemon.

set -uo pipefail

cd "$(dirname "$0")" || exit 1

REGISTRY="${REGISTRY:-ghcr.io/pyck-ai}"

command -v jq >/dev/null 2>&1 || { echo "[ERR] jq is required" >&2; exit 1; }

# buildargs.conf values are exported so verify-image.sh can assert tool versions
# against the same numbers the build used.
set -a
# shellcheck disable=SC1091
. ./buildargs.conf
set +a

targets_json=$(REGISTRY="$REGISTRY" docker buildx bake --print "$@" 2>/dev/null) || {
    echo "[ERR] could not resolve bake targets: $*" >&2
    exit 1
}

# name<TAB>first-tag,..., skipping targets that publish no tags (_common)
mapfile -t entries < <(
    echo "$targets_json" |
        jq -r '.target | to_entries[]
               | select(.value.tags != null and (.value.tags | length) > 0)
               | "\(.key)\t\(.value.tags | join(","))"'
)

[ "${#entries[@]}" -gt 0 ] || { echo "[ERR] no taggable targets matched: $*" >&2; exit 1; }

failed=0 ran=0

for entry in "${entries[@]}"; do
    IFS=$'\t' read -r target tags <<<"$entry"

    # The target name is the variant (alpine|debian). Prefer the tag that names
    # it so both variants are verified distinctly rather than both landing on
    # :latest, which only the Alpine build publishes.
    ref=""
    IFS=',' read -ra tag_list <<<"$tags"
    for t in "${tag_list[@]}"; do
        [ "${t##*:}" = "$target" ] && { ref=$t; break; }
    done
    [ -z "$ref" ] && ref=${tag_list[0]}

    if ! docker image inspect "$ref" >/dev/null 2>&1; then
        echo "[ERR] $target — image not loaded: $ref" >&2
        echo "      build it first, e.g. task verify -- $target" >&2
        failed=$((failed + 1))
        continue
    fi

    echo "▸ $target ($ref)"
    if ./verify-image.sh "$ref" "$target"; then
        ran=$((ran + 1))
    else
        failed=$((failed + 1))
    fi
done

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed image(s) failed verification ($ran passed)"
    exit 1
fi
echo "OK: $ran image(s) verified"
