#!/bin/bash
# Verifies one assembled flutter-rfw image. See verify-lib.sh for the helpers
# and verify.sh for the driver that resolves targets and calls this.
# Run via `task verify`.

. "$(dirname "$0")/verify-lib.sh"

IMG=$1
VARIANT=$2

check_user    "$IMG" nonroot 1001
check_workdir "$IMG" /app

# PUB_CACHE must resolve to the same path at build time (dart pub get, run as
# nonroot) and run time, or packages resolved during the build land somewhere
# the runtime user cannot read.
check_env "$IMG" PUB_CACHE /opt/pub-cache

# Zero-file telemetry suppression must resolve identically at build time and
# run time; see the ENV comment in the Dockerfiles for why this replaced a
# build-time `flutter config --no-analytics` call.
check_env "$IMG" FLUTTER_SUPPRESS_ANALYTICS true
check_env "$IMG" DASH__SUPPRESS_ANALYTICS true

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
