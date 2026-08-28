# Flutter Image

A Flutter + Dart runtime image with a pre-installed RFW (Remote Flutter Widgets) validator and the AWS CLI. Supports both `linux/amd64` and `linux/arm64`.

The Flutter SDK is also bundled into [`all-in-one`](../all-in-one/README.md); use this standalone image when you need the RFW validator.

## Variants

| Variant | Tag | Based on |
|---------|-----|----------|
| Alpine | `flutter:alpine` | our [base](../base/README.md) (Alpine) + Flutter SDK |
| Debian | `flutter:debian` | our [base](../base/README.md) (Debian) + Flutter SDK |

Current versions are pinned in [`buildargs.conf`](../../buildargs.conf) (`FLUTTER_VERSION`, `ALPINE_VERSION`, `DEBIAN_RELEASE`).

## Tags

### Alpine tags

| Tag | Description |
|-----|-------------|
| `flutter:latest` | Most recent Flutter version (Alpine) |
| `flutter:alpine` | Most recent Flutter version (Alpine) |
| `flutter:<major>` | Major-version alias |
| `flutter:<major>.<minor>` | Minor-version alias |
| `flutter:<version>` | Exact pinned version |
| `flutter:<major>-alpine` | Major alias on Alpine |
| `flutter:<major>.<minor>-alpine` | Minor alias on Alpine |
| `flutter:<version>-alpine` | Exact version on Alpine |

### Debian tags

| Tag | Description |
|-----|-------------|
| `flutter:debian` | Most recent Flutter version (Debian) |
| `flutter:<major>-debian` | Major alias on Debian |
| `flutter:<major>.<minor>-debian` | Minor alias on Debian |
| `flutter:<version>-debian` | Exact version on Debian |

## What is included

### Flutter toolchain

| Path | Alpine | Debian | Description |
|------|--------|--------|-------------|
| `/opt/flutter` | ✅ | ✅ | Full Flutter SDK (including bundled Dart SDK) |
| `/usr/local/bin/flutter` | ✅ | ✅ | Symlink to the flutter binary |
| `/usr/local/bin/dart` | ✅ | ✅ | Symlink to the dart binary |

Every file directly under `/opt/flutter/bin` is symlinked into `/usr/local/bin`, so `flutter` and `dart` are on `PATH`. Flutter analytics and Dart telemetry are disabled at build time.

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

The Debian variant also inherits `DEBIAN_FRONTEND` from [base](../base/README.md).

### Default user

Runs as `nonroot` (UID/GID 1001) by default. `WORKDIR` is `/app`. Uid 1001 matches the uid our GitHub Actions runners execute as, so a bind-mounted CI workspace is writable; a directory owned by a *different* uid (your local user, for instance) is **not** — mount inputs read-only and write generated output to a container-local path (see the Usage examples below). When started as `root` (the GitHub Actions path), `validate-rfw` runs `chmod -R 777 /__w` and then drops privileges to `nonroot` via `gosu` before continuing. A `flutter` account (uid/gid 1000, used to own the SDK at build time) still exists in `/etc/passwd`, but it is not the runtime user — only `nonroot` is used at container start.

Conversely, run with `--user 0` to get a root shell for installing packages or using the image as a build environment; `gosu` (see above) is how the image itself drops back from root to `nonroot` when started that way.

## Usage

There is deliberately no `ENTRYPOINT`, so `/usr/local/bin/validate-rfw` is invoked as a normal command and its first argument is the subcommand (`validate-rfw` or `generate-binary`).

### Validate an RFW file

```sh
docker run --rm -v "$PWD:/app:ro" ghcr.io/pyck-ai/baseimages/flutter:latest \
  validate-rfw validate-rfw /app/example.dart
```

The doubled word is intentional: the container command (`validate-rfw`), then the subcommand (`validate-rfw`).

### Convert text RFW to binary format

```sh
docker run --rm -v "$PWD:/app:ro" ghcr.io/pyck-ai/baseimages/flutter:latest \
  validate-rfw generate-binary /app/in.rfwtxt /tmp/out.rfw
```

### Use as a base for a Flutter app image

```dockerfile
FROM ghcr.io/pyck-ai/baseimages/flutter:latest
COPY --chown=nonroot:nonroot . /app
RUN dart pub get
```

## Build

```sh
task build -- flutter           # both alpine and debian variants
task build -- flutter-alpine    # alpine only
task build -- flutter-debian    # debian only
```
