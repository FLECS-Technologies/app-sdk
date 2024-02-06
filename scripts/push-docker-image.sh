#!/bin/bash

DOCKER_IMAGES=""
if [ ! -z "${VARIANT}" ]; then
  SUFFIX="-${VARIANT}"
fi
for archive in `find ${BUILD_CONTEXT}/out/${APP}${SUFFIX}/${VERSION} -name "*.tar"`; do
  DOCKER_IMAGE=$(docker load --quiet --input ${archive} | cut -f2- -d ':')
  run docker login --username ${DOCKER_USER} --password ${DOCKER_PASSWORD} ${DOCKER_IMAGE} >/dev/null
  DOCKER_IMAGES="${DOCKER_IMAGES} ${DOCKER_IMAGE}"
  echo "Pusing ${DOCKER_IMAGE}..."
  while ! docker push ${DOCKER_IMAGE}; do sleep 1; done
done;
DOCKER_IMAGES=`echo ${DOCKER_IMAGES} | sed 's/  / /g'`
DOCKER_MANIFEST=`echo ${DOCKER_IMAGES} | sed -E 's/^([^ ]+)-[^ ]+( |$).*/\1/'`
docker manifest rm ${DOCKER_MANIFEST} 2>/dev/null
run docker manifest create ${DOCKER_MANIFEST} ${DOCKER_IMAGES}
run docker manifest push ${DOCKER_MANIFEST}
