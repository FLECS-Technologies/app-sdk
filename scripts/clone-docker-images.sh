#!/bin/bash

APP_MANIFEST="${BUILD_CONTEXT}/out/${APP}${SUFFIX}/${VERSION}/manifest.json.compose-merged"

echo "Analyzing manifest ${APP_MANIFEST}"

HAS_COMPOSE=$(cat ${APP_MANIFEST} | jq -rc '.deployment | has ("compose")')

if [ "${HAS_COMPOSE}" != "true" ]; then
    echo "App is not a compose App -- skipping image cloning"
    return 0
fi

run docker login --username ${DOCKER_USER} --password ${DOCKER_PASSWORD} flecs.azurecr.io >/dev/null

while read IMAGE; do
    # Parse part before '/': some-registry.example.com/image:tag -> some-registry.example.com
    REGISTRY_URL=$(echo ${IMAGE} | sed -nE 's#(.*)(/.+)$#\1#p')
    if [ -n "${PRIVATE_REGISTRY_USER}" ]; then
        docker login --username ${PRIVATE_REGISTRY_USER} --password ${PRIVATE_REGISTRY_PASSWORD} ${REGISTRY_URL}
        if [ $? -ne 0 ]; then
            echo "Warning: docker login failed for ${REGISTRY_URL} -- trying to continue without authentication"
        fi
    fi
    # Parse part after '/': some-registry.example.com/image:tag -> image:tag
    BASE_IMAGE=$(echo ${IMAGE} | sed -e 's#^[^/]*/##')
    NEW_TAG="flecs.azurecr.io/${APP}${SUFFIX}/${BASE_IMAGE}"
    echo "Cloning ${IMAGE} to ${NEW_TAG}"
    # Copies directly between registries and keeps all platforms
    run docker buildx imagetools create --tag ${NEW_TAG} ${IMAGE}
    if [ -n "${PRIVATE_REGISTRY_USER}" ]; then
        run docker logout ${REGISTRY_URL}
    fi
done < <(cat "${APP_MANIFEST}" | jq -rc ".deployment.compose.yaml.services[].image")
