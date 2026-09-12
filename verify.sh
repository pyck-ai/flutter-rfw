#!/bin/sh
# shellcheck disable=SC2016
# SC2016 is silenced repo-wide: check expressions are single-quoted on purpose
# so ck() controls when eval expands them, not the shell parsing this file.
#
# Verifies the assembled flutter-rfw:alpine / flutter-rfw:debian images from
# the inside.
#
# Invoked as:
#   docker run --rm --env-file buildargs.conf -e TARGET=<alpine|debian> \
#     -v "$(pwd)/verify.sh:/verify.sh:ro" --entrypoint /bin/sh <ref> /verify.sh
#
# Transcribed 1:1 from the retired verification manifest's "*" target (9
# checks), which applied identically to both variants — diffing the alpine
# and debian sections of that spec showed no delta, so there is nothing to
# branch on $TARGET for; it is only read here to label the run in output.
#
# The original manifest's last check bind-mounted the repo root (holding the
# example.dart fixture) read-only at /app. That mount is not part of this
# script's invocation contract (only verify.sh itself is mounted in), so the
# fixture is embedded below and written to /tmp instead of relying on /app
# holding anything — /app is an empty WORKDIR in both images and is not
# guaranteed writable by the runtime user.
#
# Runs under busybox ash, dash and bash: POSIX sh only, no arrays/[[/local.

fails=0
ck() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

echo "verifying flutter-rfw variant: ${TARGET:-unset}"

# 1. user uid=1001 name="nonroot"
ck "user is uid 1001 (nonroot)" '[ "$(id -u)" = "1001" ] && [ "$(id -un)" = "nonroot" ]'

# 2. workdir value="/app"
ck "workdir is /app" '[ "$(pwd)" = "/app" ]'

# 3-5. env checks
ck "env PUB_CACHE=/opt/pub-cache" '[ "$PUB_CACHE" = "/opt/pub-cache" ]'
ck "env FLUTTER_SUPPRESS_ANALYTICS=true" '[ "$FLUTTER_SUPPRESS_ANALYTICS" = "true" ]'
ck "env DASH__SUPPRESS_ANALYTICS=true" '[ "$DASH__SUPPRESS_ANALYTICS" = "true" ]'

# 6. cmd commands=flutter,dart,validate-rfw
for c in flutter dart validate-rfw; do
  ck "command available: $c" "command -v '$c' >/dev/null"
done

# 7. version run="flutter --version" contains="$FLUTTER_VERSION"
ck "flutter --version contains \$FLUTTER_VERSION" \
  'flutter --version | grep -qF "$FLUTTER_VERSION"'

# 8. file paths=... (validator sources + entrypoint, must not silently vanish)
for p in /opt/rfw-validator/pubspec.yaml /opt/rfw-validator/pubspec.lock \
         /opt/rfw-validator/validate_rfw.dart /opt/rfw-validator/generate_binary.dart \
         /usr/local/bin/validate-rfw; do
  ck "file exists: $p" "[ -e '$p' ]"
done

# 9. sh: validate-rfw round-trip: text -> binary -> binary
# example.dart embedded here (see file header) since the repo-root mount from
# the original manifest is not part of this invocation's contract.
cat > /tmp/example.dart <<'RFWTXT_EOF'
// Example RFW (Remote Flutter Widgets) file
// This demonstrates the basic syntax and structure

import core.widgets;

// Simple example widget with a button
widget ExampleButton = Container(
    child: Column(
        children: [
          Text(text: "Hello, Flutter!"),
          ElevatedButton(
            text: "Click Me",
            onPressed: event "button_clicked" { }
          ),
        ]
    )
);

// Example form widget
widget ExampleForm = Container(
    padding: [16.0],
    child: ListView(
        children: [
          Text(text: "Example Form", style: { fontSize: 24.0 }),
          TextField(
            decoration: {
              labelText: "Enter your name",
              hintText: "John Doe"
            }
          ),
          SizedBox(height: 16.0),
          Row(
            mainAxisAlignment: "end",
            children: [
              OutlinedButton(
                text: "Cancel",
                onPressed: event "cancel" { }
              ),
              SizedBox(width: 8.0),
              ElevatedButton(
                text: "Submit",
                onPressed: event "submit" { }
              ),
            ]
          ),
        ]
    )
);
RFWTXT_EOF

ck "validate-rfw round-trip: text -> binary -> binary" '
  set -e
  validate-rfw validate-rfw /tmp/example.dart
  validate-rfw generate-binary /tmp/example.dart /tmp/example.rfw
  validate-rfw validate-rfw /tmp/example.rfw
'

exit $((fails > 0))
