#!/bin/bash

APP_MANIFEST="${BUILD_CONTEXT}/out/${APP}${SUFFIX}/${VERSION}/manifest.json.compose-merged"

echo "Analyzing manifest ${APP_MANIFEST}"

HAS_COMPOSE=$(cat ${APP_MANIFEST} | jq -rc '.deployment | has ("compose")')

if [ "${HAS_COMPOSE}" != "true" ]; then
    echo "App is not a compose App -- skipping image cloning"
fi

IMAGES=$(cat ${APP_MANIFEST} | jq -rc ".deployment.compose.yaml.services[].image")

run docker login --username ${DOCKER_USER} --password ${DOCKER_PASSWORD} flecs.azurecr.io >/dev/null

while read IMAGE; do
    # Parse part before '/': some-registry.example.com/image:tag -> some-registry.example.com
    REGISTRY_URL=$(echo ${IMAGE} | sed -nE 's#(.*)(/.+)$#\1#p')
    if [ -n "${PRIVATE_REGISTRY_USER}" ]; then
        run docker login --username ${PRIVATE_REGISTRY_USER} --password ${PRIVATE_REGISTRY_PASSWORD} ${REGISTRY_URL}
    fi
    run docker pull ${IMAGE}
    # Parse part after '/': some-registry.example.com/image:tag -> image:tag
    BASE_IMAGE=$(echo ${IMAGE} | sed -e 's#^[^/]*/##')
    NEW_TAG="flecs.azurecr.io/${APP}${SUFFIX}/${BASE_IMAGE}"
    run docker tag ${IMAGE} ${NEW_TAG}
    run docker push ${NEW_TAG}
    if [ -n "${PRIVATE_REGISTRY_USER}" ]; then
        run docker logout ${REGISTRY_URL}
    fi
done < <(cat "${APP_MANIFEST}" | jq -rc ".deployment.compose.yaml.services[].image")
