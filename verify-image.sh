#!/bin/bash
# Verifies the assembled flutter image. See docker/verify-lib.sh for the helpers.
# Run via `task verify -- flutter`.

. "$(dirname "$0")/../verify-lib.sh"

IMG=$1
VARIANT=$2

check_user    "$IMG" nonroot 1001
check_workdir "$IMG" /app

# PUB_CACHE must resolve to the same path at build time (dart pub get, run as
# nonroot) and run time, or packages resolved during the build land somewhere
# the runtime user cannot read.
check_env "$IMG" PUB_CACHE /opt/pub-cache

check_cmd "$IMG" flutter dart validate-rfw aws gosu

check_version "$IMG" "flutter --version" "$FLUTTER_VERSION"

# The two .dart scripts were dropped from the image at one point while the
# build stayed green and validate-rfw was completely dead; assert their
# presence explicitly rather than trusting a passing build.
check_file "$IMG" \
    /opt/rfw-validator/pubspec.yaml \
    /opt/rfw-validator/pubspec.lock \
    /opt/rfw-validator/validate_rfw.dart \
    /opt/rfw-validator/generate_binary.dart \
    /usr/local/bin/validate-rfw

# Real round-trip: validate-rfw has no ENTRYPOINT, so its first argument is
# the subcommand (validate-rfw|generate-binary). Bind-mount this directory
# (which holds example.dart, a valid .rfwtxt fixture) read-only at /app —
# the image runs as uid 1001 and cannot write to a host-owned mount, so the
# generated binary is written into the container's own /tmp instead.
check_host "validate-rfw round-trip: text -> binary -> binary" '
    docker run --rm --entrypoint sh \
        -v "'"$(dirname "$0")"'":/app:ro \
        "'"$IMG"'" -c "
            set -e
            validate-rfw validate-rfw /app/example.dart
            validate-rfw generate-binary /app/example.dart /tmp/example.rfw
            validate-rfw validate-rfw /tmp/example.rfw
        "
'

verify_summary
