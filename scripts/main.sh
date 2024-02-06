#!/bin/bash

BUILD_DIR=${BUILD_CONTEXT}/build

mkdir -p ${BUILD_DIR}

for VARIANT in "${VARIANTS[@]}"; do
  if [ ! -z "${SINGLE_VARIANT}" ] && [ "${VARIANT:-<default>}" != "${SINGLE_VARIANT}" ]; then
    echo "Skipping variant ${VARIANT:-<default>}"
    continue
  fi
  SUFFIX=${VARIANT:+-${VARIANT}}
  PLATFORMS=$(cat ${BUILD_CONTEXT}/docker/Docker.${VARIANT:+${VARIANT}.}platforms)
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

  if [ "${BUILD_MANIFEST}" = "true" ]; then
    source ${DIRNAME}/scripts/build-app-manifest.sh
  fi

  if [ "${PUSH_DOCKER}" = "true" ]; then
    source ${DIRNAME}/scripts/push-docker-image.sh
  fi

  if [ "${PUSH_MANIFEST}" = "true" ]; then
    source ${DIRNAME}/scripts/push-app-manifest.sh
  fi
done

rm -rf ${BUILD_CONTEXT}/build
