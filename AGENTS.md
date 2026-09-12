# Agent Instructions

This repository builds exactly one image, `ghcr.io/pyck-ai/flutter-rfw`, in two variants (Alpine, Debian) from [`Dockerfile.alpine`](Dockerfile.alpine) and [`Dockerfile.debian`](Dockerfile.debian). It was split out of [`pyck-ai/baseimages`](https://github.com/pyck-ai/baseimages) and keeps that repo's conventions.

## Base image

Both Dockerfiles start `FROM ghcr.io/pyck-ai/baseimages/base:alpine|debian`. That image supplies `download.sh`, `git`, `file`, `rsync`, `xz`, `jq` and the `nonroot` account — do not reimplement any of them here. Alpine and Debian versions are pinned in `baseimages`, not in this repo; a scheduled rebuild picks them up because the build passes `--pull`.

## Default user

The image is a runtime/deploy artifact, so it defaults to **nonroot (uid/gid 1001)** — the uid our GitHub Actions runners execute as, which is what makes a bind-mounted job workspace writable. Changing that number breaks every consumer that runs this image as a job container. `--user 0` remains the escape hatch for installing packages.

## README maintenance

[`README.md`](README.md) documents what the image contains. Keep it accurate; update it in the same change, not afterwards.

- Package added or removed: update the package table.
- Tool or validator file added, removed or renamed: update the RFW validator table and the usage examples.
- New or changed `ENV`: update the environment table.
- Default user or `WORKDIR` changed: update the "Default user" section.
- Tag scheme changed in `docker-bake.hcl`: update both tag tables.

Do not document the pinned Flutter version — it lives in `buildargs.conf` and is managed by Renovate. Do not document build-stage mechanics or CI internals; those belong in the Dockerfiles and `.github/workflows/`.

## Verification

CI verifies the exact pushed digest of each variant by running [`verify.sh`](verify.sh) **inside** the image before any tag is applied. There is no local `task verify` — a local `--load` build is not the artifact CI publishes, so it would verify something other than what ships.

When a Dockerfile changes, update `verify.sh` in the same change:

- Tool added, removed or renamed: update the relevant version/command checks.
- New or changed `ENV`: update the env checks.
- Default user or `WORKDIR` changed: update the user/workdir checks.
- New file the image must ship: add a check for it.

Ground every check in the Dockerfile, and prefer checks that exercise real behaviour (the round-trip check) over ones that only assert a variable is set.

`verify.sh` is invoked as `docker run --rm --env-file buildargs.conf -e TARGET=<alpine|debian> -v "$(pwd)/verify.sh:/verify.sh:ro" --entrypoint /bin/sh <ref> /verify.sh`, so `buildargs.conf` values (like `FLUTTER_VERSION`) are compared directly with no templating layer, and it is runnable by hand the same way.

## CI

[`build.yml`](.github/workflows/build.yml) delegates to the shared `pyck-ai/github-actions` build-image workflow, which discovers the matrix, builds, runs `verify.sh` inside each pushed digest, and publishes tags. Host networking for BuildKit is configured by `docker/setup-buildx-action` inside that shared workflow, never in the `Taskfile.yml` — the Taskfile must keep working under rootless Docker locally.
