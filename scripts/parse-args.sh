#!/bin/bash

SCRIPTNAME=$(basename $(readlink -f ${0}))

print_usage() {
  echo "usage: ${SCRIPTNAME} [-a | --app <app>] [-v | --version <version>] [-p | --push]
                    [--variant <variant>] [-m | --manifest-only] [-i | --image-only]
                    [-h | --help] [-d | --debug]"
}

parse_args() {
  local ARG_DOCKER_ONLY="false"
  while [ ! -z "${1}" ]; do
    case ${1} in
      -a|--app)
        # Trim trailing '/'', if specified
        local ARG_APP=${2/%\/}
        shift
        ;;
      -v|--version)
        local ARG_VERSION=${2}
        shift
        ;;
      --variant)
        local ARG_VARIANT=${2}
        shift
        ;;
      -p|--push)
        local ARG_PUSH="true"
        ;;
      -m|--manifest-only)
        local ARG_MANIFEST_ONLY="true"
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      -d|--debug)
        DEBUG="true"
        ;;
      *)
        echo "Unknown argument ${1}" 1>&2
        exit 1
    esac
    shift
  done

  BUILD_DOCKER="true"

  if [ "${ARG_PUSH}" = "true" ]; then
    PUSH_DOCKER="true"
    PUSH_MANIFEST="true"
  fi

  if [ "${ARG_MANIFEST_ONLY}" = "true" ]; then
    BUILD_DOCKER="false"
    PUSH_DOCKER="false"
  fi

  if [ "${DEBUG}" = "true" ]; then
    echo "*** Debug: arguments" 1>&2
    echo "  * ARG_APP: ${ARG_APP}" 1>&2
    echo "  * ARG_VERSION: ${ARG_VERSION}" 1>&2
    echo "  * ARG_VARIANT: ${ARG_VARIANT}" 1>&2
    echo "  * ARG_PUSH: ${ARG_PUSH}" 1>&2
    echo "  * ARG_MANIFEST_ONLY: ${ARG_MANIFEST_ONLY}" 1>&2
    echo
  fi

  if [ -z "${ARG_APP}" ]; then
    print_usage
    echo "Error: No <app> specified" 1>&2
    exit 1
  fi

  if [ -z "${ARG_VERSION}" ]; then
    print_usage
    echo "Error: No <version> specified" 1>&2
    exit 1
  fi

  APP=${ARG_APP}
  VERSION=${ARG_VERSION}
  SINGLE_VARIANT=${ARG_VARIANT}
}

parse_args $*

#BUILD_CONTEXT=$(dirname $(readlink -f ${0}))/${APP}
BUILD_CONTEXT=$(pwd)/${APP}
if [ "${DEBUG}" = "true" ]; then
  echo "*** Debug: variables"
  echo "  * APP: ${APP}"
  echo "  * VERSION: ${VERSION}"
  echo "  * SINGLE_VARIANT: ${SINGLE_VARIANT}"
  echo "  * BUILD_DOCKER: ${BUILD_DOCKER}"
  echo "  * PUSH_DOCKER: ${PUSH_DOCKER}"
  echo "  * PUSH_MANIFEST: ${PUSH_MANIFEST}"
  echo "  * BUILD_CONTEXT: ${BUILD_CONTEXT}"
  echo
fi

# Apps can have different variants, specified by a manifest named 'manifest.<var>.json'
# A Manifest named 'manifest.var.json' yields an App variant named <app>-var
VARIANTS=()
for MANIFEST in $(find ${BUILD_CONTEXT} -mindepth 1 -maxdepth 1 -name "manifest*"); do
  VARIANTS+=("$(basename ${MANIFEST} | sed -nr 's/manifest\.([^.]*)\.?json/\1/p')")
done

if [ "${#VARIANTS[@]}" = 0 ]; then
  echo "No variants found, nothing to build..." 1>&2
  exit 1
fi

echo "Found ${#VARIANTS[@]} variants"

if [ "${DEBUG}" = "true" ]; then
  echo "*** Debug: variants"
  for VARIANT in "${VARIANTS[@]}"; do
    if [ "${VARIANT}" = "" ]; then
      echo "  * <default>"
    else
      echo "  * ${VARIANT}"
    fi
  done
  echo
fi
