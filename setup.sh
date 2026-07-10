#!/bin/bash
set -euo pipefail

# Resolve paths relative to this script so it works from any working directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR/vm"
terraform init
terraform apply --auto-approve

# The "kubeconfig" output is a talos_cluster_kubeconfig object, not a plain
# string, so `terraform output -raw` won't work here — extract the YAML block.
terraform output kubeconfig > "$SCRIPT_DIR/kubeconfig"
sed -i -n '/apiVersion/,$p' "$SCRIPT_DIR/kubeconfig"
sed -i '/EOT/,$d' "$SCRIPT_DIR/kubeconfig"

echo "Talos cluster provisioned. kubeconfig written to $SCRIPT_DIR/kubeconfig"
echo "Run the following command with sudo privileges to add the route to the workers:"
echo "sudo ip route add 100.64.100.101 via $(terraform output -json worker_ips | jq -r '.[0]')"
echo "Next: hand this kubeconfig to your CNI/workload repo (e.g. talos-educates) to finish setting up the cluster."
