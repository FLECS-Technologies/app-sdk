#!/bin/bash

APP_MANIFEST="${BUILD_CONTEXT}/out/${APP}${SUFFIX}/${VERSION}/manifest.json"

echo "Creating manifest ${APP_MANIFEST}"

LOCAL_APP_MANIFEST="${BUILD_CONTEXT}/manifest.${VARIANT:+${VARIANT}.}json"

run cp "${LOCAL_APP_MANIFEST}" "${APP_MANIFEST}"

run sed -i "s/##VERSION##/${VERSION}/g" "${APP_MANIFEST}"
