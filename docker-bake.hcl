# Docker Bake configuration for the flutter-rfw image.
#
# Build args are read from buildargs.conf via environment variables. Task
# sources that file before calling bake.
#
# Usage:
#   task build             # both variants
#   task build -- alpine   # Alpine only
#
# Or directly with docker:
#   set -a && source buildargs.conf && set +a && docker buildx bake

variable "REGISTRY" {
  default = "ghcr.io/pyck-ai"
}

variable "FLUTTER_VERSION" {}

# Returns the version tags for a 1-, 2- or 3-part version, each optionally
# suffixed with the variant.
# Example: vtags("3.38.1", "-alpine")
#   → [flutter-rfw:3.38.1-alpine, flutter-rfw:3.38-alpine, flutter-rfw:3-alpine]
function "vtags" {
  params = [version, suffix]
  result = concat(
    ["${REGISTRY}/flutter-rfw:${version}${suffix}"],
    length(split(".", version)) >= 2 ? ["${REGISTRY}/flutter-rfw:${split(".", version)[0]}.${split(".", version)[1]}${suffix}"] : [],
    ["${REGISTRY}/flutter-rfw:${split(".", version)[0]}${suffix}"]
  )
}

target "_common" {
  context = "."
  # Declared here rather than left to the caller: `task build` also passes
  # --set *.args.FLUTTER_VERSION, but a bare `docker buildx bake` would
  # otherwise build with an empty ARG and fail deep inside the SDK download
  # with a checksum lookup that matches nothing.
  args = {
    FLUTTER_VERSION = FLUTTER_VERSION
  }
  platforms = [
    "linux/amd64",
    "linux/arm64",
  ]
}

group "default" {
  targets = [
    "alpine",
    "debian",
  ]
}

target "alpine" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile.alpine"
  tags = concat(
    ["${REGISTRY}/flutter-rfw:latest", "${REGISTRY}/flutter-rfw:alpine"],
    vtags(FLUTTER_VERSION, ""),
    vtags(FLUTTER_VERSION, "-alpine"),
  )
  cache-from = ["type=registry,ref=${REGISTRY}/flutter-rfw/buildcache:alpine"]
  cache-to   = ["type=registry,ref=${REGISTRY}/flutter-rfw/buildcache:alpine,mode=max"]
}

target "debian" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile.debian"
  tags = concat(
    ["${REGISTRY}/flutter-rfw:debian"],
    vtags(FLUTTER_VERSION, "-debian"),
  )
  cache-from = ["type=registry,ref=${REGISTRY}/flutter-rfw/buildcache:debian"]
  cache-to   = ["type=registry,ref=${REGISTRY}/flutter-rfw/buildcache:debian,mode=max"]
}
