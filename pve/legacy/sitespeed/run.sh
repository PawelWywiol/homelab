#!/bin/bash

WEBSITE=$1

if [ -z "$1" ]; then
  echo "Please provide the website url as the first argument"
  exit 1
fi

WEBSITE_HOSTNAME=$(echo $WEBSITE | awk -F/ '{print $3}')
WEBSITE_SLUG=$(echo $WEBSITE_HOSTNAME | sed -e 's/[^[:alnum:]]/_/g' | tr -s '_' | tr A-Z a-z)
WEBSITE_SLUG=$(echo $WEBSITE_SLUG | sed -e 's/^www_//')

NAMESPACE="sitespeed_io.default"
RESULT_BASE_URL="http://192.168.0.107:8081/sitespeed-result/"
DOCKER_NETWORK="code_default"

echo "Running sitespeed.io for $WEBSITE ($WEBSITE_SLUG)"

docker run --rm \
  --network $DOCKER_NETWORK \
  --cap-add NET_ADMIN \
  -v "$(pwd):/sitespeed.io" sitespeedio/sitespeed.io \
  -c 4g \
  $WEBSITE \
  --slug $WEBSITE_SLUG \
  --graphite.host graphite \
  --graphite.namespace $NAMESPACE \
  --graphite.addSlugToKey true \
  --copyLatestFilesToBase true \
  --resultBaseURL "$RESULT_BASE_URL" \
  --video true \
  --screenshot true \
  --screenshot.type jpg \
  --browsertime.connectivity.engine throttle \
  --mobile \
  --browsertime.chrome.mobileEmulation.deviceName "iPhone SE" \
  --browsertime.chrome.includeResponseBodies html \
  --axe.enable \
  --cpu \
  --thirdParty.cpu

docker run --rm \
  --network $DOCKER_NETWORK \
  -v "$(pwd):/sitespeed.io" sitespeedio/sitespeed.io \
  $WEBSITE \
  --slug $WEBSITE_SLUG \
  --graphite.host graphite \
  --graphite.namespace $NAMESPACE \
  --graphite.addSlugToKey true \
  --copyLatestFilesToBase true \
  --resultBaseURL "$RESULT_BASE_URL" \
  --video true \
  --screenshot true \
  --screenshot.type jpg \
  --browsertime.chrome.includeResponseBodies html \
  --axe.enable \
  --cpu \
  --thirdParty.cpu

for file in ./sitespeed-result/$WEBSITE_SLUG/*.{json,png,jpg,jpeg,mp4}; do
  [ -e "$file" ] || continue

  if [[ $(basename "$file") != $NAMESPACE* ]]; then
    mv "$file" "$(dirname "$file")/$NAMESPACE.$(basename "$file")"
  fi
done
