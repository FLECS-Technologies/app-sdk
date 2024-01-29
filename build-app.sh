#!/bin/bash

run() {
  "$@" || exit 1
}

DIRNAME=$(dirname $(readlink -f ${0}))

source ${DIRNAME}/scripts/parse-args.sh

echo "Building app ${APP} in context ${BUILD_CONTEXT}"

source ${DIRNAME}/scripts/main.sh
