# vm-macos — Talos on Apple Silicon (QEMU + HVF)

## Install

- An Apple Silicon Mac
- [`tofu`](https://opentofu.org/docs/intro/install/)
- `jq`
- Homebrew `socket_vmnet`: `brew install qemu socket_vmnet`. It needs a
  **root** daemon running before `tofu apply` — either
  `sudo brew services start socket_vmnet` (persists across reboots) or,
  for a one-off session:
  ```bash
  mkdir -p /opt/homebrew/var/run
  sudo /opt/homebrew/opt/socket_vmnet/bin/socket_vmnet \
    --vmnet-gateway=192.168.105.1 --vmnet-mask=255.255.255.0 \
    /opt/homebrew/var/run/socket_vmnet
  ```
  The default socket path (`/opt/homebrew/var/run/socket_vmnet`) and client binary
  path are overridable via the `socket_vmnet_socket`/`socket_vmnet_client`
  variables.
- A non-scoped host route to the vmnet subnet via `bridge100` (see
  **Architecture** below) — [scripts/qemu-up.sh](scripts/qemu-up.sh) adds
  it automatically via `sudo` before booting each VM
- An **arm64** Talos ISO. Default path is `/mnt/talos/metal-arm64.iso`,
  override with the `iso_path` variable.
- UEFI firmware: `edk2-aarch64-code.fd` / `edk2-arm-vars.fd`, used by
  default. Override via the `firmware_code`/`firmware_vars_template`
  variables if your install differs.

## Quickstart

```bash
tofu init
tofu apply -var cluster_name=talos
```

`cluster_name` is required. Override other variables with `-var` or a
varsfile passed via `-var-file`; see [variables.tf](variables.tf) for node
counts, CPU, memory, disk size, and firmware/vmnet settings.

`tofu apply` writes a ready-to-use `talosctl` client config to
`./talosconfig` (via the `local_file.talosconfig` resource). Use it to
pull a kubeconfig directly from the cluster:

```bash
talosctl kubeconfig --talosconfig=./talosconfig \
  --nodes "$(tofu output -raw cp_vm_ip_address)" .
```

VM disks, per-VM UEFI NVRAM copies, and pidfiles live under
`var.vm_state_dir` (default `./.vms`, relative to this directory).

## Teardown

```bash
tofu destroy
```

## Architecture

- **Networking**: [`socket_vmnet`](https://github.com/lima-vm/socket_vmnet)
  — a root daemon owns the `vmnet.framework` interface; unprivileged QEMU
  connects over a Unix socket via `socket_vmnet_client`
  (`-netdev socket,fd=3`). Avoids requiring QEMU to carry Apple's
  restricted `com.apple.vm.networking` entitlement.
- **IP discovery**: [scripts/find-ip.sh](scripts/find-ip.sh) polls macOS's
  bootpd lease file (`/var/db/dhcpd_leases`) for each VM's MAC address.
- **DNS**: `socket_vmnet`'s gateway (`socket_vmnet_gateway`, `192.168.105.1`
  by default, see **Install**) is handed out via DHCP as the nameserver
  but doesn't run a DNS relay. [main.tf](main.tf) sets
  `machine.network.nameservers` explicitly to `1.1.1.1`/`8.8.8.8` instead.
- **Diagnostics**: each VM's serial console is captured to
  `<state_dir>/<name>-serial.log` (`-serial file:...`).

## Folder layout

| Path | Purpose |
|------|---------|
| [main.tf](main.tf) | machine config, bootstrap, kubeconfig, VM wiring |
| [scripts/](scripts/) | qemu-up.sh / qemu-down.sh / find-ip.sh |
| [variables.tf](variables.tf) | tunables incl. firmware + socket_vmnet paths |

## License

[MIT](../LICENSE)
