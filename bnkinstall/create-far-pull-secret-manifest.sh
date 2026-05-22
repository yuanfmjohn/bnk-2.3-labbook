#!/bin/bash

# Store the service account key in SERVICE_ACCOUNT_KEY.
# The name of the file that contains the service account key may be
# provided as the first argument to this script. If not,
# the filename defaults to ../cne_pull_64.json.
SERVICE_ACCOUNT_KEY=$(cat ${1:-../cne_pull_64.json})

# Create the SERVICE_ACCOUNT_K8S_SECRET variable by prefixing SERVICE_ACCOUNT_KEY with "_json_key_base64:".
SERVICE_ACCOUNT_K8S_SECRET=$(echo "_json_key_base64:${SERVICE_ACCOUNT_KEY}" | base64 -w 0)

cat <<EOF > far-pull-secret.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: far-pull-secret
data:
  .dockerconfigjson: $(echo '{"auths": {"repo.f5.com": {"auth": "'$SERVICE_ACCOUNT_K8S_SECRET'"}}}' \
    | base64 -w 0)
type: kubernetes.io/dockerconfigjson
EOF
