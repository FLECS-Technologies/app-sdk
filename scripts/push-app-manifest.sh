#!/bin/bash

AZ="az"
if ! command -v az &>/dev/null; then
  CONTAINER_ID=`docker run -it -d -v ${DIRNAME}:${DIRNAME} -w ${DIRNAME} mcr.microsoft.com/azure-cli:latest`
  AZ="docker exec ${CONTAINER_ID} az"
fi

run ${AZ} login --service-principal --username ${AZ_CLIENT_ID} --tenant ${AZ_TENANT_ID} --password ${AZ_CLIENT_SECRET} >/dev/null
for manifest in `find ${BUILD_CONTEXT}/out/${APP}/${VERSION} -name "manifest.json"`; do
  run ${AZ} storage blob upload --auth-mode login --account-name flecs --container-name flecs-apps --name ${APP}/${VERSION}/$(basename ${manifest}) --file ${manifest} --overwrite
done;
${AZ} logout
if [ "${CONTAINER_ID}" != "" ]; then
  docker rm -f ${CONTAINER_ID} &>/dev/null
fi
