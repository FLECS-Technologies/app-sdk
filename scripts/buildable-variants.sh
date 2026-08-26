#!/bin/bash
# Print the variants of an App whose base image exists for a given version.
# The unnamed variant is printed as <default>. Reasons go to stderr.
#
# Variants track upstream images that release independently, so a version may
# exist for one and not another. A variant is only left out when its base image
# is known to be absent; anything else is printed.
#
# Usage: buildable-variants.sh <app-dir> <version>

set -eu

APP_DIR="${1:?usage: buildable-variants.sh <app-dir> <version>}"
VERSION="${2:?usage: buildable-variants.sh <app-dir> <version>}"

# Prints the base image of a variant, or fails if there is none to resolve.
resolve_base() {
  local variant="${1}" dockerfile base

  dockerfile="${APP_DIR}/docker/Dockerfile${variant:+.${variant}}"
  [ -f "${dockerfile}" ] || dockerfile="${APP_DIR}/docker/Dockerfile"
  [ -f "${dockerfile}" ] || return 1

  base=$(grep '^FROM' "${dockerfile}" \
    | grep -viE '[[:space:]]as[[:space:]]' | head -1 | awk '{print $2}')
  [ -n "${base}" ] || return 1

  base=${base//\$\{VARIANT\}/${variant}}
  base=${base//\$\{VERSION\}/${VERSION}}
  printf '%s' "${base}"
}

# 0 = build this variant, 1 = leave it out.
buildable() {
  local variant="${1}" label="${1:-<default>}" base

  base=$(resolve_base "${variant}") || {
    echo "${label}: no Dockerfile" 1>&2
    return 0
  }

  case "${base}" in
    *'${'*)
      echo "${label}: ${base} has unresolved build args" 1>&2
      return 0
      ;;
    # compose Apps: images come from docker-compose.yml
    scratch|scratch:*)
      echo "${label}: base image is scratch" 1>&2
      return 0
      ;;
    *:*) ;;
    *)
      echo "${label}: ${base} is untagged" 1>&2
      return 0
      ;;
  esac

  # Private images need credentials to inspect.
  if [ -n "${PRIVATE_REGISTRY:-}" ]; then
    echo "${label}: private registry in use" 1>&2
    return 0
  fi

  if docker manifest inspect "${base}" >/dev/null 2>&1; then
    echo "${label}: ${base} exists" 1>&2
    return 0
  fi

  echo "${label}: ${base} does not exist" 1>&2
  return 1
}

for MANIFEST in "${APP_DIR}"/manifest*.json; do
  [ -e "${MANIFEST}" ] || continue
  NAME=$(basename "${MANIFEST}")

  if [ "${NAME}" = "manifest.json" ]; then
    VARIANT=""
  else
    VARIANT=$(sed -nE 's/^manifest\.([^.]+)\.json$/\1/p' <<<"${NAME}")
    [ -n "${VARIANT}" ] || continue
  fi

  if buildable "${VARIANT}"; then
    printf '%s\n' "${VARIANT:-<default>}"
  fi
done
