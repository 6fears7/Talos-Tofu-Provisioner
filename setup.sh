#!/bin/bash
set -euo pipefail

# Resolve paths relative to this script so it works from any working directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR/vm"
tofu init
tofu apply --auto-approve

# Extraction is done with awk (not `sed -i`) so it behaves identically under
# GNU and BSD sed/awk (macOS ships BSD sed, which needs a different -i syntax).
tofu output kubeconfig > "$SCRIPT_DIR/kubeconfig.tmp"
awk '/apiVersion/{f=1} f && /EOT/{exit} f' "$SCRIPT_DIR/kubeconfig.tmp" > "$SCRIPT_DIR/kubeconfig"
rm -f "$SCRIPT_DIR/kubeconfig.tmp"

if ! grep -q '^apiVersion' "$SCRIPT_DIR/kubeconfig" || ! grep -q '^clusters:' "$SCRIPT_DIR/kubeconfig"; then
  echo "ERROR: extracted kubeconfig at $SCRIPT_DIR/kubeconfig looks malformed" >&2
  exit 1
fi

# kubeconfig contains the cluster admin's client cert/key in cleartext.
chmod 600 "$SCRIPT_DIR/kubeconfig"

echo "Talos cluster provisioned. kubeconfig written to $SCRIPT_DIR/kubeconfig"

worker_ip="$(tofu output -json worker_ips | jq -r '.[0] // empty')"
if [ -n "$worker_ip" ]; then
  echo "Run the following command with sudo privileges to add the route to the workers:"
  echo "sudo ip route add 100.64.100.101 via $worker_ip"
else
  echo "WARNING: no worker IPs found (worker_count may be 0) — skipping route command."
fi
echo "Next: hand this kubeconfig to your CNI/workload repo (e.g. talos-educates) to finish setting up the cluster."
