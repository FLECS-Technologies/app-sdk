#!/bin/bash

BUILD_DIR=${BUILD_CONTEXT}/build

mkdir -p ${BUILD_DIR}

for VARIANT in "${VARIANTS[@]}"; do
  if [ ! -z "${SINGLE_VARIANT}" ] && [ "${VARIANT:-<default>}" != "${SINGLE_VARIANT}" ]; then
    echo "Skipping variant ${VARIANT:-<default>}"
    continue
  fi
  SUFFIX=${VARIANT:+-${VARIANT}}

  # Look for platform-specific Docker.${VARIANT}.platforms
  PLATFORM_FILE="${BUILD_CONTEXT}/docker/Docker.${VARIANT:+${VARIANT}.}platforms"
  echo -n "Checking for ${PLATFORM_FILE} ... "
  if [ ! -f "${PLATFORM_FILE}" ]; then
    echo "no"
    PLATFORM_FILE="${BUILD_CONTEXT}/docker/Docker.platforms"
    echo -n "Checking for ${PLATFORM_FILE} ... "
    # Use platform-independent Docker.platforms as fallback
    if [ ! -f "${PLATFORM_FILE}" ]; then
      echo "no"
      echo "fatal: no usable Docker.platforms file found" 1>&1
      exit 1
    else
      echo "yes"
    fi
  else
    echo "yes"
  fi

  PLATFORMS=$(cat ${PLATFORM_FILE})
  OUT_DIR=${BUILD_CONTEXT}/out/${APP}${SUFFIX}/${VERSION}
  mkdir -p ${OUT_DIR}

  if [ "${BUILD_DOCKER}" = "true" ]; then
    for PLATFORM in ${PLATFORMS//,/ }; do
      case ${PLATFORM} in
      linux/arm/v7)
        export ARCH=armhf
        ;;
      linux/amd64)
        export ARCH=amd64
        ;;
      linux/arm64)
        export ARCH=arm64
        ;;
      *)
        echo "Invalid platform ${PLATFORM}" 1>&2
        exit 1
        ;;
      esac

      source ${DIRNAME}/scripts/build-docker-image.sh
    done
  fi

  source ${DIRNAME}/scripts/build-app-manifest.sh

  if [ "${PUSH_DOCKER}" = "true" ]; then
    source ${DIRNAME}/scripts/clone-docker-images.sh
    source ${DIRNAME}/scripts/push-docker-image.sh
  fi

  if [ "${PUSH_MANIFEST}" = "true" ]; then
    source ${DIRNAME}/scripts/push-app-manifest.sh
  fi
done

rm -rf ${BUILD_CONTEXT}/build
