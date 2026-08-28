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

[`verify.sh`](verify.sh) resolves the bake targets and runs [`verify-image.sh`](verify-image.sh) against each built image; [`verify-lib.sh`](verify-lib.sh) holds the helpers. Run it with `task verify`.

When a Dockerfile changes, update `verify-image.sh` in the same change:

- Tool added, removed or renamed: update the `check_cmd` / `check_version` calls.
- New or changed `ENV`: update `check_env`.
- Default user or `WORKDIR` changed: update `check_user` / `check_workdir`.
- New file the image must ship: add it to `check_file`.

Ground every check in the Dockerfile, and prefer checks that exercise real behaviour (the round-trip `check_host`) over ones that only assert a variable is set.

`verify-lib.sh` is a **vendored copy** of `docker/verify-lib.sh` in `pyck-ai/baseimages`. Fix bugs in both, and keep the helper API identical so the two do not drift into incompatible dialects.

## CI

`build.yml` discovers its matrix from `docker-bake.hcl`, so adding a variant needs no workflow edit. Host networking for BuildKit is configured by `docker/setup-buildx-action` in the workflow, never in the `Taskfile.yml` — the Taskfile must keep working under rootless Docker locally.
