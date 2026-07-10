#!/bin/bash
# Implements the `data "external"` protocol: reads a JSON object with a
# "host" key (and optional "timeout" in seconds) from stdin, polls the
# Kubernetes API server's /version endpoint until it responds, and prints
# {"ready": "true"} to stdout on success.
#
# talos_machine_bootstrap completing doesn't mean kube-apiserver is already
# accepting connections — etcd still needs to elect a leader and the
# apiserver needs to finish starting, which takes up to a couple of minutes.
# helm_release.cilium has no retry of its own, so without this wait it fails
# immediately with "connection refused" and needs a manual re-apply.
set -euo pipefail

query="$(cat)"
host="$(echo "$query" | jq -r '.host')"
timeout_seconds="$(echo "$query" | jq -r '.timeout // "180"')"

deadline=$((SECONDS + timeout_seconds))
while [ "$SECONDS" -lt "$deadline" ]; do
  if curl -sk --max-time 3 "https://${host}:6443/version" >/dev/null 2>&1; then
    echo '{"ready": "true"}'
    exit 0
  fi
  sleep 2
done

echo "wait-for-apiserver: timed out after ${timeout_seconds}s waiting for https://${host}:6443/version to respond" >&2
exit 1
