# flutter-rfw

A Flutter + Dart image with a pre-installed RFW (Remote Flutter Widgets) validator and the AWS CLI, published as `ghcr.io/pyck-ai/flutter-rfw`. Supports `linux/amd64` and `linux/arm64`.

Split out of [`pyck-ai/baseimages`](https://github.com/pyck-ai/baseimages), where it was published as `ghcr.io/pyck-ai/baseimages/flutter`. That name is frozen and no longer built.

## Variants

| Variant | Tag | Based on |
|---------|-----|----------|
| Alpine | `flutter-rfw:alpine` | `ghcr.io/pyck-ai/baseimages/base:alpine` + Flutter SDK |
| Debian | `flutter-rfw:debian` | `ghcr.io/pyck-ai/baseimages/base:debian` + Flutter SDK |

The Flutter version is pinned in [`buildargs.conf`](buildargs.conf). The Alpine and Debian versions are not pinned here — they belong to the base images and arrive with each scheduled rebuild.

## Tags

### Alpine tags

| Tag | Description |
|-----|-------------|
| `flutter-rfw:latest` | Most recent Flutter version (Alpine) |
| `flutter-rfw:alpine` | Most recent Flutter version (Alpine) |
| `flutter-rfw:<major>` | Major-version alias |
| `flutter-rfw:<major>.<minor>` | Minor-version alias |
| `flutter-rfw:<version>` | Exact pinned version |
| `flutter-rfw:<major>-alpine` | Major alias on Alpine |
| `flutter-rfw:<major>.<minor>-alpine` | Minor alias on Alpine |
| `flutter-rfw:<version>-alpine` | Exact version on Alpine |

### Debian tags

| Tag | Description |
|-----|-------------|
| `flutter-rfw:debian` | Most recent Flutter version (Debian) |
| `flutter-rfw:<major>-debian` | Major alias on Debian |
| `flutter-rfw:<major>.<minor>-debian` | Minor alias on Debian |
| `flutter-rfw:<version>-debian` | Exact version on Debian |

## What is included

### Flutter toolchain

| Path | Alpine | Debian | Description |
|------|--------|--------|-------------|
| `/opt/flutter` | ✅ | ✅ | Full Flutter SDK (including bundled Dart SDK) |
| `/usr/local/bin/flutter` | ✅ | ✅ | Symlink to the flutter binary |
| `/usr/local/bin/dart` | ✅ | ✅ | Symlink to the dart binary |

Every file directly under `/opt/flutter/bin` is symlinked into `/usr/local/bin`, so `flutter` and `dart` are on `PATH`. Flutter analytics and Dart telemetry are suppressed via environment variables that apply at both build time and run time.

### arm64 notes

Flutter only ships a Linux x86_64 release archive. For `linux/arm64` builds the image automatically:

1. Replaces the bundled x86_64 Dart SDK with an arm64 build downloaded from the Dart archive.
2. Clears pre-compiled snapshots and engine artifacts so Flutter regenerates them for arm64.
3. Runs `flutter precache` to download arm64 engine artifacts and recompile `flutter_tools.snapshot`.

The precache result is persisted in a BuildKit cache mount keyed by Flutter version + arch, so repeat arm64 builds restore in seconds rather than recompiling.

### RFW validator

Pre-installed at `/opt/rfw-validator`. Validates Remote Flutter Widgets (RFW) files for syntax errors.

| File | Description |
|------|-------------|
| `/opt/rfw-validator/pubspec.yaml` | Pub dependencies for the validator |
| `/opt/rfw-validator/pubspec.lock` | Resolved/pinned dependency versions, produced by `dart pub get` at build time |
| `/opt/rfw-validator/validate_rfw.dart` | Validates `.rfwtxt` (text) and `.rfw` (binary) files |
| `/opt/rfw-validator/generate_binary.dart` | Converts text RFW to binary format |
| `/usr/local/bin/validate-rfw` | Wrapper script (`validate-rfw.sh`) for simplified CLI use |

### Packages

| Package | Alpine | Debian | Purpose |
|---------|--------|--------|---------|
| AWS CLI | `aws-cli` | `awscli` | Pushing build artefacts to S3/ECR from CI |
| gosu | `gosu` | `gosu` | Privilege drop when the container is started as root |
| OpenGL | `glu` | `libglu1-mesa` | Required by the Flutter engine |
| C++ runtime | _(via gcompat)_ | `libgcc-s1`, `libstdc++6` | Required by the Flutter engine |

### Environment

| Variable | Value | Description |
|----------|-------|--------------|
| `PUB_CACHE` | `/opt/pub-cache` | Dart pub cache directory; resolves identically at build time and run time |
| `FLUTTER_SUPPRESS_ANALYTICS` | `true` | Suppresses Flutter analytics regardless of `$HOME` |
| `DASH__SUPPRESS_ANALYTICS` | `true` | Suppresses Dart telemetry regardless of `$HOME` |

The Debian variant also inherits `DEBIAN_FRONTEND` from the base image.

### Default user

Runs as `nonroot` (UID/GID 1001) by default. `WORKDIR` is `/app`. Uid 1001 matches the uid our GitHub Actions runners execute as, so a bind-mounted CI workspace is writable; a directory owned by a *different* uid (your local user, for instance) is **not** — mount inputs read-only and write generated output to a container-local path (see the Usage examples below). When started as `root` (the GitHub Actions path), `validate-rfw` runs `chmod -R 777 /__w` and then drops privileges to `nonroot` via `gosu` before continuing.

Conversely, run with `--user 0` to get a root shell for installing packages or using the image as a build environment; `gosu` (see above) is how the image itself drops back from root to `nonroot` when started that way.

## Usage

There is deliberately no `ENTRYPOINT`, so `/usr/local/bin/validate-rfw` is invoked as a normal command and its first argument is the subcommand (`validate-rfw` or `generate-binary`).

### Validate an RFW file

```sh
docker run --rm -v "$PWD:/app:ro" ghcr.io/pyck-ai/flutter-rfw:latest \
  validate-rfw validate-rfw /app/example.dart
```

The doubled word is intentional: the container command (`validate-rfw`), then the subcommand (`validate-rfw`).

### Convert text RFW to binary format

```sh
docker run --rm -v "$PWD:/app:ro" ghcr.io/pyck-ai/flutter-rfw:latest \
  validate-rfw generate-binary /app/in.rfwtxt /tmp/out.rfw
```

### Use as a base for a Flutter app image

```dockerfile
FROM ghcr.io/pyck-ai/flutter-rfw:latest
COPY --chown=nonroot:nonroot . /app
RUN dart pub get
```

## Build

```sh
task setup             # create the buildx builder (once per machine)
task build             # both variants, for the host architecture
task build -- alpine   # Alpine only
task build ARCH=arm64  # cross-build for arm64
```

## Verifying

`task verify` builds the images with `--load` and then checks the *assembled* result — default user, `WORKDIR`, `ENV`, tool versions against `buildargs.conf`, the validator's files, and a real text → binary → validate round trip:

```sh
task verify            # both variants
task verify -- alpine  # Alpine only
```

The checks live in [`verify-image.sh`](verify-image.sh); [`verify-lib.sh`](verify-lib.sh) is a copy of the shared helper library from `pyck-ai/baseimages`.
