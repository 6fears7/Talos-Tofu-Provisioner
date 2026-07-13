#!/bin/bash
set -euo pipefail

# Resolve paths relative to this script so it works from any working directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

reset_network=0
clean=0
iso_path=""
worker_count="1"
# Must match vm-macos/variables.tf's cp_memory/worker_memory defaults —
# bash can't read the .tf default, so it's duplicated here deliberately.
# Whatever these resolve to is what the RAM preflight below validates
# *and* what's actually passed to tofu apply, so the two never diverge.
cp_memory="4"
worker_memory="4"
while [ $# -gt 0 ]; do
  case "$1" in
    --reset-network) reset_network=1; shift ;;
    --clean) clean=1; shift ;;
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
    --cp-memory)
      [ $# -ge 2 ] || { echo "ERROR: --cp-memory requires a value" >&2; exit 1; }
      cp_memory="$2"
      shift 2
      ;;
    --worker-memory)
      [ $# -ge 2 ] || { echo "ERROR: --worker-memory requires a value" >&2; exit 1; }
      worker_memory="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument '$1' (supported: --reset-network, --clean, --iso-path <path>, --worker-count <n>, --cp-memory <gib>, --worker-memory <gib>)" >&2
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
case "$cp_memory" in
  ''|*[!0-9]*)
    echo "ERROR: --cp-memory must be a non-negative integer (GiB), got '$cp_memory'" >&2
    exit 1
    ;;
esac
case "$worker_memory" in
  ''|*[!0-9]*)
    echo "ERROR: --worker-memory must be a non-negative integer (GiB), got '$worker_memory'" >&2
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

if [ "$clean" = 1 ]; then
  if [ "$target" != "macos" ]; then
    echo "ERROR: --clean only applies to the macOS backend (TARGET=macos); the Linux/libvirt backend manages VM volumes through the provider." >&2
    exit 1
  fi

  # tofu destroy deliberately leaves per-VM qcow2 disks and UEFI NVRAM in
  # place (see qemu-down.sh — mirrors libvirt_volume surviving a domain
  # destroy). But qemu-up.sh reuses any existing disk and boots it before
  # the ISO (-boot order=cd), so a destroy->apply cycle silently reboots
  # the *old* Talos install under a *new* apply's freshly-generated
  # machine secrets — a stale-PKI/etcd mismatch that can stop nodes from
  # joining. --clean is the explicit opt-in to a true clean slate, keeping
  # destroy itself non-destructive. VM_STATE_DIR mirrors the vm_state_dir
  # tofu variable (default ./.vms, relative to the apply cwd = the module).
  vm_state_dir="${VM_STATE_DIR:-.vms}"
  clean_dir="$SCRIPT_DIR/$tf_dir/$vm_state_dir"
  if [ -d "$clean_dir" ]; then
    echo "Wiping VM disks/NVRAM in $clean_dir..."
    # Serial/.log files are left alone: pure diagnostics, overwritten on
    # next boot. Globs may not match after a prior clean, so tolerate that.
    rm -f "$clean_dir"/talos-*.qcow2 "$clean_dir"/talos-*-vars.fd
    echo "VM disks/NVRAM cleaned."
  else
    echo "No VM state dir at $clean_dir; nothing to clean."
  fi
fi

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
  # vmnet's own stock default. A CGNAT range (100.64.0.0/10, matching
  # vm/'s vpn-safe-net libvirt network) was tried here to dodge the same
  # class of VPN split-tunnel route collision that 192.168.x.x risks, but
  # Apple's vmnet.framework hard-rejects any gateway outside RFC1918
  # space (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) with VMNET_FAILURE
  # — confirmed against vmnet.h's undocumented start/end-address comments
  # and matching reports from VMware Fusion/VirtualBox/UTM on non-RFC1918
  # vmnet ranges. Must match the socket_vmnet_gateway/socket_vmnet_mask
  # tofu variables in vm-macos/, and must stay within RFC1918 space if
  # ever overridden — see the preflight check below.
  socket_vmnet_gateway="${SOCKET_VMNET_GATEWAY:-192.168.105.1}"
  socket_vmnet_mask="${SOCKET_VMNET_MASK:-255.255.255.0}"

  case "$socket_vmnet_gateway" in
    10.*) ;;
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) ;;
    192.168.*) ;;
    *)
      echo "ERROR: socket_vmnet_gateway '$socket_vmnet_gateway' is outside RFC1918 private address space." >&2
      echo "Apple's vmnet.framework only accepts 10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16 gateways and hard-rejects anything else (e.g. CGNAT's 100.64.0.0/10) with VMNET_FAILURE, undocumented but confirmed via vmnet.h and matching reports from other vmnet.framework consumers (VMware Fusion, VirtualBox, UTM)." >&2
      exit 1
      ;;
  esac

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
  # Captured (rather than left attached to the terminal) so a VMNET_FAILURE
  # exit can be pattern-matched below and turned into a specific fix instead
  # of a generic "run it manually to see why".
  daemon_log="$(mktemp -t socket_vmnet.log)"
  sudo "$socket_vmnet_bin" --vmnet-gateway="$socket_vmnet_gateway" --vmnet-mask="$socket_vmnet_mask" "$socket_vmnet_socket" >"$daemon_log" 2>&1 &
  daemon_pid=$!
  disown

  ready=0
  for _ in $(seq 1 20); do
    if ! sudo kill -0 "$daemon_pid" 2>/dev/null; then
      # The preflight check above already rules out a non-RFC1918 gateway
      # (the most common cause of this error — see its comment), so a
      # VMNET_FAILURE here more likely means macOS has a *different*
      # RFC1918 subnet cached from a prior run (of this daemon on another
      # gateway, or another vmnet-based tool like Lima/UTM/Docker Desktop)
      # at /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
      # — clearing it requires a reboot to take effect.
      if grep -q VMNET_FAILURE "$daemon_log" 2>/dev/null; then
        echo "ERROR: socket_vmnet failed to start vmnet.framework (VMNET_FAILURE) despite $socket_vmnet_gateway being valid RFC1918 space." >&2
        echo "macOS likely has a different shared-network subnet cached from a prior run (of this daemon on another gateway, or another vmnet-based tool like Lima/UTM/Docker Desktop)." >&2
        echo "Fix: clear the cache and reboot (required — a daemon restart alone won't reload it), then retry:" >&2
        echo "  sudo rm /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist" >&2
      else
        echo "ERROR: socket_vmnet exited immediately after starting; run it manually to see why:" >&2
        echo "  sudo $socket_vmnet_bin --vmnet-gateway=$socket_vmnet_gateway --vmnet-mask=$socket_vmnet_mask $socket_vmnet_socket" >&2
      fi
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
  rm -f "$daemon_log"
  echo "socket_vmnet restarted."
fi

if [ "$target" = "macos" ]; then
  # QEMU/HVF doesn't refuse to start when the host is over-committed —
  # it just degrades until something hangs. Confirmed the hard way: 3
  # VMs x 8GB (the old defaults) on a 24GB host silently hung one
  # worker's guest kernel mid-boot (memory-accounting BUG, no further
  # progress) instead of failing loudly. Catch it before tofu apply
  # instead.
  total_mem_gib=$((cp_memory + worker_memory * worker_count))
  host_mem_gib=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
  # 80% ceiling leaves headroom for macOS + QEMU/HVF overhead per VM.
  safe_mem_gib=$((host_mem_gib * 80 / 100))
  if [ "$total_mem_gib" -gt "$safe_mem_gib" ]; then
    echo "ERROR: requested guest memory (cp_memory=$cp_memory + worker_memory=$worker_memory * worker_count=$worker_count = ${total_mem_gib}GiB) exceeds 80% of this host's ${host_mem_gib}GiB RAM." >&2
    echo "Lower --cp-memory/--worker-memory or --worker-count — an overcommitted host doesn't fail cleanly, it hangs a VM mid-boot." >&2
    exit 1
  fi
fi

tofu_vars=(-var "worker_count=$worker_count" -var "cp_memory=$cp_memory" -var "worker_memory=$worker_memory")
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
