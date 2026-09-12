#!/bin/sh
# Verifies the assembled flutter-rfw:alpine / flutter-rfw:debian images from
# the inside.
#
# Invoked as:
#   docker run --rm --env-file buildargs.conf -e TARGET=<alpine|debian> \
#     -v "$(pwd)/verify.sh:/verify.sh:ro" --entrypoint /bin/sh <ref> /verify.sh
#
# Transcribed 1:1 from the retired verification manifest's "*" target (9
# checks, identical across both variants — diffing the alpine and debian
# sections of that spec showed no delta, so there is nothing to branch on
# $TARGET for; it is only read here to label the run in output).
#
# The original manifest's last check bind-mounted the repo root (holding the
# example.dart fixture) read-only at /app. That mount is not part of this
# script's invocation contract (only verify.sh itself is mounted in), so a
# minimal fixture is embedded below and written to /tmp instead of relying on
# /app holding anything — /app is an empty WORKDIR in both images and is not
# guaranteed writable by the runtime user. The fixture only needs to be *a*
# valid .rfwtxt file to prove the toolchain round-trips text -> binary ->
# binary, so it is trimmed to a single widget rather than duplicating the
# repo's real example.dart, which would otherwise silently drift from it.
#
# Runs under busybox ash, dash and bash: POSIX sh only, no arrays/[[/local.

fails=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

check_user() {
    if [ "$(id -u)" = "$1" ] && [ "$(id -un)" = "$2" ]; then
        ok "user is uid $1 ($2)"
    else
        bad "user is uid $(id -u) ($(id -un)), want $1 ($2)"
    fi
}

check_workdir() {
    if [ "$(pwd)" = "$1" ]; then ok "workdir is $1"; else bad "workdir is $(pwd), want $1"; fi
}

check_env() {
    if [ "$(printenv "$1")" = "$2" ]; then ok "env $1=$2"; else bad "env $1=$(printenv "$1"), want $2"; fi
}

check_cmd() {
    for c in "$@"; do
        if command -v "$c" >/dev/null 2>&1; then
            ok "command available: $c"
        else
            bad "command available: $c"
        fi
    done
}

# Runs a command and looks for a substring, so a version bump in buildargs.conf
# fails the check instead of silently passing.
check_version() {
    out=$(sh -c "$1" 2>&1)
    case "$out" in
        *"$2"*) ok "$1 reports $2" ;;
        *)      bad "$1 does not report $2: $out" ;;
    esac
}

check_file() {
    for f in "$@"; do
        if [ -e "$f" ]; then ok "file exists: $f"; else bad "file exists: $f"; fi
    done
}

echo "verifying flutter-rfw variant: ${TARGET:-unset}"

check_user 1001 nonroot
check_workdir /app

check_env PUB_CACHE /opt/pub-cache
check_env FLUTTER_SUPPRESS_ANALYTICS true
check_env DASH__SUPPRESS_ANALYTICS true

check_cmd flutter dart validate-rfw

check_version "flutter --version" "$FLUTTER_VERSION"

# Validator sources + entrypoint, must not silently vanish.
check_file /opt/rfw-validator/pubspec.yaml /opt/rfw-validator/pubspec.lock \
    /opt/rfw-validator/validate_rfw.dart /opt/rfw-validator/generate_binary.dart \
    /usr/local/bin/validate-rfw

cat > /tmp/verify.rfwtxt <<'RFWTXT_EOF'
import core.widgets;
widget Main = Text(text: "hi");
RFWTXT_EOF

if validate-rfw validate-rfw /tmp/verify.rfwtxt \
    && validate-rfw generate-binary /tmp/verify.rfwtxt /tmp/verify.rfw \
    && validate-rfw validate-rfw /tmp/verify.rfw; then
    ok "validate-rfw round-trip: text -> binary -> binary"
else
    bad "validate-rfw round-trip: text -> binary -> binary"
fi

exit $((fails > 0))
