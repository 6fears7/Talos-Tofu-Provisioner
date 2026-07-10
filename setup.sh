#!/bin/bash
set -euo pipefail

# Resolve paths relative to this script so it works from any working directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

reset_network=0
iso_path=""
worker_count="1"
while [ $# -gt 0 ]; do
  case "$1" in
    --reset-network) reset_network=1; shift ;;
    --iso-path)
      [ $# -ge 2 ] || { echo "ERROR: --iso-path requires a value" >&2; exit 1; }
      iso_path="$2"
      shift 2
      ;;
    --worker-count)
      [ $# -ge 2 ] || { echo "ERROR: --worker-count requires a value" >&2; exit 1; }
      worker_count="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument '$1' (supported: --reset-network, --iso-path <path>, --worker-count <n>)" >&2
      exit 1
      ;;
  esac
done

case "$worker_count" in
  ''|*[!0-9]*)
    echo "ERROR: --worker-count must be a non-negative integer, got '$worker_count'" >&2
    exit 1
    ;;
esac

# Pick a backend: TARGET=linux|macos overrides; otherwise detect from uname.
target="${TARGET:-}"
if [ -z "$target" ]; then
  case "$(uname -s)" in
    Darwin) target="macos" ;;
    Linux) target="linux" ;;
    *)
      echo "ERROR: unrecognized OS $(uname -s); set TARGET=linux or TARGET=macos explicitly." >&2
      exit 1
      ;;
  esac
fi

case "$target" in
  linux) tf_dir="vm" ;;
  macos) tf_dir="vm-macos" ;;
  *)
    echo "ERROR: unknown TARGET '$target' (expected linux or macos)" >&2
    exit 1
    ;;
esac

if [ "$reset_network" = 1 ]; then
  if [ "$target" != "macos" ]; then
    echo "ERROR: --reset-network only applies to the macOS backend (TARGET=macos)" >&2
    exit 1
  fi

  # Stale bridge/ARP state can accumulate on socket_vmnet after many VM
  # start/stop cycles against the same long-running daemon, leaving new VMs
  # unreachable from the host. Killing and restarting it clears that state.
  # Overridable to match non-default socket_vmnet_socket/_client tofu vars.
  socket_vmnet_bin="${SOCKET_VMNET_BIN:-$(brew --prefix)/opt/socket_vmnet/bin/socket_vmnet}"
  socket_vmnet_socket="${SOCKET_VMNET_SOCKET:-/opt/homebrew/var/run/socket_vmnet}"
  socket_vmnet_gateway="${SOCKET_VMNET_GATEWAY:-192.168.105.1}"

  echo "Restarting socket_vmnet..."
  sudo pkill -f socket_vmnet || true
  for _ in $(seq 1 20); do
    pgrep -f "$socket_vmnet_bin" >/dev/null 2>&1 || break
    sleep 0.5
  done

  # pkill only stops the daemon process; it doesn't unlink the socket file
  # it was bound to. If it's left behind, the new daemon can fail to bind
  # ("address already in use") and exit immediately, while the stale file
  # still passes a bare `-S` check below — a false "it's ready".
  sudo rm -f "$socket_vmnet_socket"

  mkdir -p "$(dirname "$socket_vmnet_socket")"
  sudo "$socket_vmnet_bin" --vmnet-gateway="$socket_vmnet_gateway" "$socket_vmnet_socket" &
  daemon_pid=$!
  disown

  ready=0
  for _ in $(seq 1 20); do
    if ! sudo kill -0 "$daemon_pid" 2>/dev/null; then
      echo "ERROR: socket_vmnet exited immediately after starting; run it manually to see why:" >&2
      echo "  sudo $socket_vmnet_bin --vmnet-gateway=$socket_vmnet_gateway $socket_vmnet_socket" >&2
      exit 1
    fi
    if [ -S "$socket_vmnet_socket" ]; then
      ready=1
      break
    fi
    sleep 0.5
  done
  if [ "$ready" != 1 ]; then
    echo "ERROR: socket_vmnet did not come up (no socket at $socket_vmnet_socket)" >&2
    exit 1
  fi
  echo "socket_vmnet restarted."
fi

tofu_vars=(-var "worker_count=$worker_count")
if [ -n "$iso_path" ]; then
  tofu_vars+=(-var "iso_path=$iso_path")
fi

cd "$SCRIPT_DIR/$tf_dir"
tofu init
tofu apply --auto-approve "${tofu_vars[@]}"

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

if [ "$target" = "linux" ]; then
  worker_ip="$(tofu output -json worker_ips | jq -r '.[0] // empty')"
  if [ -n "$worker_ip" ]; then
    echo "Run the following command with sudo privileges to add the route to the workers:"
    echo "sudo ip route add 100.64.100.101 via $worker_ip"
  else
    echo "WARNING: no worker IPs found (worker_count may be 0) — skipping route command."
  fi
else
  # The macOS backend routes VM traffic through the socket_vmnet daemon,
  # which puts VM IPs directly on a subnet the host can already reach — no
  # equivalent manual route needed.
  echo "Nodes are reachable directly over vmnet; no extra route needed from the host."
fi
echo "Cilium is installed as the cluster's CNI; the cluster is ready for workloads."
echo "Use the cluster with:"
echo "  export KUBECONFIG=$SCRIPT_DIR/kubeconfig"
echo "  kubectl get nodes"
echo "Next: see https://github.com/6fears7/Educates-Examples for example workshops/workloads to deploy."
