#!/bin/bash
# Creates (if needed) and boots a QEMU/HVF VM on Apple Silicon.
# Idempotent: safe to call again against an already-running VM (no-op) or
# an already-created disk (reused, not recreated).
set -euo pipefail

usage() {
  echo "Usage: $0 <name> <mac> <cpu> <memory_gib> <disk_gib> <iso_path> <state_dir> <firmware_code> <firmware_vars_template> <socket_vmnet_client> <socket_vmnet_socket> <socket_vmnet_gateway> <socket_vmnet_mask>" >&2
  exit 1
}
[ $# -eq 13 ] || usage

name="$1"
mac="$2"
cpu="$3"
memory_gib="$4"
disk_gib="$5"
iso_path="$6"
state_dir="$7"
firmware_code="$8"
firmware_vars_template="$9"
socket_vmnet_client="${10}"
socket_vmnet_socket="${11}"
socket_vmnet_gateway="${12}"
socket_vmnet_mask="${13}"

if [ ! -S "$socket_vmnet_socket" ]; then
  echo "qemu-up: $socket_vmnet_socket is not a socket. Start the daemon first:" >&2
  echo "  sudo \$(brew --prefix)/opt/socket_vmnet/bin/socket_vmnet --vmnet-gateway=$socket_vmnet_gateway --vmnet-mask=$socket_vmnet_mask $socket_vmnet_socket" >&2
  exit 1
fi

# macOS scopes the route to the vmnet subnet (IFSCOPE) to whatever process
# is bound to the bridge interface vmnet.framework created for the
# gateway ($socket_vmnet_gateway), e.g. bootpd for DHCP. An ordinary
# unscoped process — like the talos terraform provider pushing machine
# config, or talosctl/kubectl talking to a node — falls back to the
# global default route instead and the connection just hangs (confirmed:
# indefinite SYN_SENT sourced from the primary interface, never reaching
# the VM). A non-scoped route for the whole subnet fixes host-to-guest
# reachability for every process, not just interface-bound system daemons.
#
# The interface is detected rather than hardcoded to "bridge100":
# vmnet.framework assigns whatever bridgeN is next free, which varies by
# host (e.g. the built-in Thunderbolt Bridge already claims bridge0, and
# other vmnet-based tools like Docker Desktop/Lima/Parallels can claim
# more), so a fixed name isn't portable across Macs.
gateway_regex="$(echo "$socket_vmnet_gateway" | sed 's/\./\\./g')"
vmnet_iface="$(ifconfig | awk -F: -v pat="inet ${gateway_regex} " '/^[a-zA-Z0-9]+:/ {iface=$1} $0 ~ pat {print iface; exit}')"

# Network address = gateway AND mask, octet by octet (both are plain
# dotted-quads); avoids assuming the subnet is always a /24.
network="$(IFS=. read -r g1 g2 g3 g4 <<<"$socket_vmnet_gateway"
  IFS=. read -r m1 m2 m3 m4 <<<"$socket_vmnet_mask"
  echo "$((g1 & m1)).$((g2 & m2)).$((g3 & m3)).$((g4 & m4))")"

if [ -z "$vmnet_iface" ]; then
  echo "qemu-up: warning: couldn't find the interface owning $socket_vmnet_gateway; skipping host route setup." >&2
  echo "qemu-up: host-to-guest connections (config apply, talosctl, kubectl) may hang until a route is added manually, e.g.:" >&2
  echo "  sudo route -n add -net $network -netmask $socket_vmnet_mask -interface bridge100  # substitute the actual bridgeN" >&2
else
  # Idempotent: "File exists" means a prior run (or the host) already added it.
  route_add_output="$(sudo route -n add -net "$network" -netmask "$socket_vmnet_mask" -interface "$vmnet_iface" 2>&1)" || {
    case "$route_add_output" in
      *"File exists"*) ;;
      *)
        echo "qemu-up: warning: could not add host route for $network/$socket_vmnet_mask via $vmnet_iface: $route_add_output" >&2
        echo "qemu-up: host-to-guest connections (config apply, talosctl, kubectl) may hang until this is added manually:" >&2
        echo "  sudo route -n add -net $network -netmask $socket_vmnet_mask -interface $vmnet_iface" >&2
        ;;
    esac
  }
fi

mkdir -p "$state_dir"

disk="$state_dir/${name}.qcow2"
vars="$state_dir/${name}-vars.fd"
pidfile="$state_dir/${name}.pid"
logfile="$state_dir/${name}.log"
serialfile="$state_dir/${name}-serial.log"

if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  echo "qemu-up: $name already running (pid $(cat "$pidfile"))" >&2
  exit 0
fi
rm -f "$pidfile"

if [ ! -f "$disk" ]; then
  qemu-img create -f qcow2 "$disk" "${disk_gib}G" >&2
fi

if [ ! -f "$vars" ]; then
  cp "$firmware_vars_template" "$vars"
fi

# virtio-rng-pci: without a virtual RNG device, Talos's userspace hangs
# indefinitely right after handing off from the initramfs (confirmed on
# real hardware — no further boot output for 9+ minutes at 100% CPU),
# almost certainly blocked on entropy for its first-boot cert/key
# generation.
#
# Direct `-netdev vmnet-shared` requires QEMU itself to carry the
# restricted com.apple.vm.networking entitlement, which Gatekeeper won't
# honor for an ad-hoc-signed Homebrew binary (confirmed on real hardware:
# "cannot create vmnet interface: general failure" in every privilege
# combination). socket_vmnet sidesteps this: a separately root-run, signed
# daemon owns the vmnet.framework interface, and unprivileged QEMU talks to
# it over a Unix socket via the socket_vmnet_client wrapper, which execs
# qemu-system-aarch64 with fd 3 connected to the daemon.
"$socket_vmnet_client" "$socket_vmnet_socket" \
  qemu-system-aarch64 \
  -name "$name" \
  -M virt \
  -accel hvf \
  -cpu host \
  -smp "$cpu" \
  -m "${memory_gib}G" \
  -drive if=pflash,format=raw,readonly=on,file="$firmware_code" \
  -drive if=pflash,format=raw,file="$vars" \
  -drive if=virtio,format=qcow2,file="$disk" \
  -cdrom "$iso_path" \
  -boot order=cd \
  -device virtio-rng-pci \
  -netdev socket,id=net0,fd=3 \
  -device virtio-net-pci,netdev=net0,mac="$mac" \
  -display none \
  -serial file:"$serialfile" \
  -daemonize \
  -pidfile "$pidfile" \
  >>"$logfile" 2>&1

echo "qemu-up: $name started (pid $(cat "$pidfile"))" >&2
