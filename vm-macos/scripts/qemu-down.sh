#!/bin/bash
# Stops a VM started by qemu-up.sh, via its pidfile. Leaves the disk/NVRAM
# files in place (mirrors libvirt_volume surviving a libvirt_domain destroy
# unless explicitly removed).
set -euo pipefail

usage() {
  echo "Usage: $0 <name> <state_dir>" >&2
  exit 1
}
[ $# -eq 2 ] || usage

name="$1"
state_dir="$2"
pidfile="$state_dir/${name}.pid"

if [ ! -f "$pidfile" ]; then
  echo "qemu-down: no pidfile for $name, nothing to do" >&2
  exit 0
fi

pid="$(cat "$pidfile")"
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid"
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  kill -9 "$pid" 2>/dev/null || true
fi

rm -f "$pidfile"
echo "qemu-down: $name stopped" >&2
