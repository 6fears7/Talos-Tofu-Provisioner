#!/bin/bash
# Implements the `data "external"` protocol: reads a JSON object with a
# "mac" key (and optional "timeout" in seconds) from stdin, polls macOS's
# bootpd DHCP lease file for a matching entry, and prints {"ip": "..."} to
# stdout on success. All progress/diagnostic output goes to stderr, since
# the external data source requires stdout to contain only the result JSON.
#
# Confirmed on real hardware: /var/db/dhcpd_leases is what macOS's bootpd
# populates for socket_vmnet guests, and it's readable without sudo.
set -euo pipefail

query="$(cat)"
mac="$(echo "$query" | jq -r '.mac')"
timeout_seconds="$(echo "$query" | jq -r '.timeout // "300"')"
lease_file="/var/db/dhcpd_leases"
mac_lc="$(echo "$mac" | tr 'A-Z' 'a-z')"

find_lease_ip() {
  [ -r "$lease_file" ] || return 1
  # bootpd writes each MAC octet without a leading zero (e.g. "2:70:f5:..."
  # not "02:70:f5:..."), while our generated MACs always have a leading
  # zero on the first octet (locally-administered bit) and can have one on
  # any octet. Normalize both sides the same way before comparing, or
  # every lookup silently times out despite the lease existing.
  awk -v mac="$mac_lc" '
    function normalize(m,    n, i, parts, out) {
      n = split(tolower(m), parts, ":")
      out = ""
      for (i = 1; i <= n; i++) {
        if (length(parts[i]) == 2 && substr(parts[i], 1, 1) == "0") parts[i] = substr(parts[i], 2, 1)
        out = out (i > 1 ? ":" : "") parts[i]
      }
      return out
    }
    BEGIN { target = normalize(mac) }
    /^{/ { ip=""; hw="" }
    /ip_address=/ { split($0,a,"="); ip=a[2] }
    /hw_address=/ { split($0,a,"="); hw=a[2]; sub(/^1,/,"",hw); hw=normalize(hw) }
    /^}/ { if (hw==target && ip!="") print ip }
  ' "$lease_file" | tail -n1
}

elapsed=0
interval=5
ip=""
while [ "$elapsed" -lt "$timeout_seconds" ]; do
  ip="$(find_lease_ip || true)"
  [ -n "$ip" ] && break
  sleep "$interval"
  elapsed=$((elapsed + interval))
done

if [ -z "$ip" ]; then
  echo "find-ip: timed out after ${timeout_seconds}s waiting for a DHCP lease for $mac (checked $lease_file)" >&2
  exit 1
fi

jq -n --arg ip "$ip" '{ip: $ip}'
