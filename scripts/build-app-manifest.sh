#!/bin/bash

APP_MANIFEST="${BUILD_CONTEXT}/out/${APP}${SUFFIX}/${VERSION}/manifest.json"

echo "Creating manifest ${APP_MANIFEST}"

LOCAL_APP_MANIFEST="${BUILD_CONTEXT}/manifest.${VARIANT:+${VARIANT}.}json"

run cp "${LOCAL_APP_MANIFEST}" "${APP_MANIFEST}"

run sed -i "s/##VERSION##/${VERSION}/g" "${APP_MANIFEST}"

if [ -f "${BUILD_CONTEXT}/docker/docker-compose.yml" ]; then
    echo "Merging docker-compose.yml into manifest"
    COMPOSE_YAML=$(cat ${BUILD_CONTEXT}/docker/docker-compose.yml | yq -o json -M)
    run jq ".deployment.compose |= . + ${COMPOSE_YAML}" "${APP_MANIFEST}" >${APP_MANIFEST}.compose-merged

    echo "Replacing images in App manifest"
    run cat "${APP_MANIFEST}.compose-merged" | jq -rc '.deployment.compose.services[].image |= sub("(^[^/]*/)"; "flecs.azurecr.io/'"${APP}${SUFFIX}"'/")' >"${APP_MANIFEST}"
fi
