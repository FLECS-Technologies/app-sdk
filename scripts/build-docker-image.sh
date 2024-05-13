#!/bin/bash

DOCKER_TAG="flecs.azurecr.io/${APP}${SUFFIX}:${VERSION}-${ARCH}"
DOCKER_ARCHIVE="${BUILD_CONTEXT}/out/${APP}${SUFFIX}/${VERSION}/data_${ARCH}.tar"
echo "Building ${DOCKER_TAG} (platform ${PLATFORM}) to ${DOCKER_ARCHIVE}"

# look for variant-specific Dockerfile, fallback to 'Dockerfile', if not found
DOCKERFILE="${BUILD_CONTEXT}/docker/Dockerfile${VARIANT:+.${VARIANT}}"
if [ ! -f "${DOCKERFILE}" ]; then
  DOCKERFILE="${BUILD_CONTEXT}/docker/Dockerfile"
fi
# Check if a private registry should be used and login if necessary
if [ ! -z "${PRIVATE_REGISTRY}" ]; then
  run docker login --username ${PRIVATE_REGISTRY_USER} --password ${PRIVATE_REGISTRY_PASSWORD} ${PRIVATE_REGISTRY} >/dev/null
fi
echo "Using Dockerfile ${DOCKERFILE}"
run docker buildx build \
  --progress=plain \
  --pull \
  --load \
  --build-arg ARCH=${ARCH} \
  --build-arg VARIANT=${VARIANT} \
  --build-arg VERSION=${VERSION} \
  --platform ${PLATFORM} \
  --tag ${DOCKER_TAG} \
  --file ${DOCKERFILE} \
  ${DOCKER_ARGS} ${BUILD_CONTEXT}

run mkdir -p $(realpath -m $(dirname ${DOCKER_ARCHIVE}))
run docker save --output ${DOCKER_ARCHIVE} ${DOCKER_TAG}

# Check if a private registry was used and logout if necessary
if [ ! -z "${PRIVATE_REGISTRY}" ]; then
  run docker logout ${PRIVATE_REGISTRY} >/dev/null
fi