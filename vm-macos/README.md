# vm-macos — Talos on Apple Silicon (QEMU + HVF)

OpenTofu module that provisions a Talos Kubernetes cluster on Apple
Silicon: QEMU accelerated by Apple's Hypervisor.framework (HVF),
networked via `vmnet.framework`. VM lifecycle and networking are driven
directly by [scripts/](scripts/) instead of a provider. See the root
[README.md](../README.md) for how this backend relates to [vm/](../vm).

Talos secrets/certs are generated the same way as the Linux backend, via
the shared [../modules/talos_secrets](../modules/talos_secrets) module.
OpenTofu stores state in plaintext; treat `terraform.tfstate` as
sensitive.

## Install

- An Apple Silicon Mac; [`tofu`](https://opentofu.org/docs/intro/install/),
  `jq`.
- Homebrew `socket_vmnet`: `brew install qemu socket_vmnet`. It needs a
  **root** daemon running before `tofu apply` — either
  `sudo brew services start socket_vmnet` (persists across reboots) or,
  for a one-off session:
  ```bash
  mkdir -p /opt/homebrew/var/run
  sudo /opt/homebrew/opt/socket_vmnet/bin/socket_vmnet \
    --vmnet-gateway=192.168.105.1 /opt/homebrew/var/run/socket_vmnet
  ```
  The default socket path (`/opt/homebrew/var/run/socket_vmnet`) and
  client binary path are overridable via the `socket_vmnet_socket`/
  `socket_vmnet_client` variables.
- A non-scoped host route to `192.168.105.0/24` via `bridge100` (see
  **Architecture** below) — [scripts/qemu-up.sh](scripts/qemu-up.sh) adds
  it automatically via `sudo` before booting each VM (see
  **Troubleshooting** if it can't prompt for a password).
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
- **DNS**: `socket_vmnet`'s gateway (`192.168.105.1` by convention, see
  **Install**) is handed out via DHCP as the nameserver but doesn't run a
  DNS relay. [main.tf](main.tf) sets `machine.network.nameservers`
  explicitly to `1.1.1.1`/`8.8.8.8` instead.
- **Host reachability**: macOS scopes the route to `192.168.105.0/24` via
  `bridge100` (`IFSCOPE`) to whichever process is bound to that interface
  (e.g. `bootpd` for DHCP). Ordinary unscoped processes — the `talos`
  terraform provider pushing machine config, `talosctl`, `kubectl` — fall
  back to the default route instead and hang indefinitely (`SYN_SENT`
  sourced from the primary interface, never reaching the VM).
  [scripts/qemu-up.sh](scripts/qemu-up.sh) adds a non-scoped route for the
  subnet before booting each VM to fix this for every process, not just
  system daemons; see **Troubleshooting** if it can't prompt for a
  password.
- **Diagnostics**: each VM's serial console is captured to
  `<state_dir>/<name>-serial.log` (`-serial file:...`)

## How it differs from vm/

| | [vm/](../vm) (Linux) | vm-macos (this module) |
|---|---|---|
| Acceleration | KVM | Apple Hypervisor.framework (HVF) |
| VM lifecycle | `libvirt_domain`/`libvirt_volume` (dmacvicar/libvirt provider) | `terraform_data` + `local-exec` calling [scripts/qemu-up.sh](scripts/qemu-up.sh)/[qemu-down.sh](scripts/qemu-down.sh) |
| Networking | libvirt NAT network (`vpn-safe-net`, bridge + dnsmasq) | `socket_vmnet` daemon + Apple's `vmnet.framework` |
| IP discovery | `data.libvirt_domain_interface_addresses` (reads libvirt's DHCP lease) | `data.external` calling [scripts/find-ip.sh](scripts/find-ip.sh) (reads macOS's bootpd lease file) |
| Disk device seen by Talos | `/dev/sda` (IDE) | `/dev/vda` (virtio) |
| Firmware | libvirt's default SeaBIOS-style boot | explicit UEFI (`edk2-aarch64-code.fd` + per-VM NVRAM) |

Talos secrets/cert generation, machine configuration, bootstrap,
kubeconfig assembly are shared or mirror [vm/main.tf](../vm/main.tf)
resource-for-resource.

## Folder layout

| Path | Purpose |
|------|---------|
| [main.tf](main.tf) | machine config, bootstrap, kubeconfig, VM wiring |
| [scripts/](scripts/) | qemu-up.sh / qemu-down.sh / find-ip.sh |
| [variables.tf](variables.tf) | tunables incl. firmware + socket_vmnet paths |

## License

[MIT](../LICENSE)
