#!/bin/sh

# To run this script:
# ./get-cne-chart-version.sh <chartName>
# or
# ./get-cne-chart-version.sh <chartFilePath>
#
# Example (chart located in the charts directory; specify only the chart name):
# ./get-cne-chart-version.sh cwc
#
# Example (chart located in a directory other than charts; specify the chart's filepath):
# ./get-cne-chart-version.sh utils/f5-cert-gen

# Ensure CNE_RELEASE_MANIFEST_VERSION is set
if [ -z "${CNE_RELEASE_MANIFEST_VERSION:-}" ]; then
  echo "Error: CNE_RELEASE_MANIFEST_VERSION is not set. Please set this environment variable and try again." >&2
  exit 1
fi

case "$1" in
    */*) chart_path="$1" ;;
      *) chart_path="charts/$1" ;;
esac

CHART_PATH="$chart_path"
  yq -r --arg V "$CNE_RELEASE_MANIFEST_VERSION" --arg C "$CHART_PATH" \
    '.releases[]
    | select(.version == $V)
    | .helm_charts[]
    | select(.name == $C)
    | .version
  ' bigip-k8s-manifest-$CNE_RELEASE_MANIFEST_VERSION.yaml
