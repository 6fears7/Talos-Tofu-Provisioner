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
    --vmnet-gateway=192.168.105.1 --vmnet-mask=255.255.255.0 \
    /opt/homebrew/var/run/socket_vmnet
  ```
  The gateway/mask must match the `socket_vmnet_gateway`/
  `socket_vmnet_mask` tofu variables exactly, or
  [scripts/qemu-up.sh](scripts/qemu-up.sh)'s interface detection (see
  **Architecture**) silently fails. They default to vmnet's own stock
  `192.168.105.1`/`255.255.255.0`. A CGNAT gateway (`100.64.x.x`, matching
  [vm/](../vm)'s `vpn-safe-net` libvirt network) was tried here for a time
  to dodge VPN split-tunnel route collisions on `192.168.x.x`, but Apple's
  `vmnet.framework` hard-rejects any gateway outside RFC1918 private space
  (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) with an undocumented
  `VMNET_FAILURE` — see **Troubleshooting**. Any override of
  `socket_vmnet_gateway` must stay within RFC1918 space. The default
  socket path (`/opt/homebrew/var/run/socket_vmnet`) and client binary
  path are overridable via the `socket_vmnet_socket`/`socket_vmnet_client`
  variables.
- A non-scoped host route to the vmnet subnet via `bridge100` (see
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
- **DNS**: `socket_vmnet`'s gateway (`socket_vmnet_gateway`, `192.168.105.1`
  by default, see **Install**) is handed out via DHCP as the nameserver
  but doesn't run a DNS relay. [main.tf](main.tf) sets
  `machine.network.nameservers` explicitly to `1.1.1.1`/`8.8.8.8` instead.
- **Host reachability**: macOS scopes the route to the vmnet subnet via
  `bridge100` (`IFSCOPE`) to whichever process is bound to that interface
  (e.g. `bootpd` for DHCP). Ordinary unscoped processes — the `talos`
  terraform provider pushing machine config, `talosctl`, `kubectl` — fall
  back to the default route instead and hang indefinitely (`SYN_SENT`
  sourced from the primary interface, never reaching the VM).
  [scripts/qemu-up.sh](scripts/qemu-up.sh) adds a non-scoped route for the
  subnet (derived from the `socket_vmnet_gateway`/`socket_vmnet_mask`
  variables, not hardcoded) before booting each VM to fix this for every
  process, not just system daemons; see **Troubleshooting** if it can't
  prompt for a password.
- **Diagnostics**: each VM's serial console is captured to
  `<state_dir>/<name>-serial.log` (`-serial file:...`)

## Troubleshooting

- **`VMNET_FAILURE` from `socket_vmnet` / `vmnet_start_interface`**: almost
  always means `socket_vmnet_gateway` is outside RFC1918 private space
  (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`). Apple's
  `vmnet.framework` hard-rejects any other range — e.g. CGNAT's
  `100.64.0.0/10` — with this error, undocumented but confirmed via
  `vmnet.h`'s start/end-address comments and matching reports from other
  vmnet.framework consumers (VMware Fusion, VirtualBox, UTM). No amount of
  restarting the daemon fixes this; the gateway itself has to change.
  `setup.sh --reset-network` checks this before even trying to start the
  daemon and fails fast with the same explanation.
  If `socket_vmnet_gateway` *is* already RFC1918 and you still hit
  `VMNET_FAILURE`, the likelier cause is `vmnet.framework` having a
  *different* RFC1918 subnet cached system-wide from a prior run (this
  daemon on another gateway, or another vmnet-based tool like Lima/UTM/
  Docker Desktop). Clear it and reboot (a daemon restart alone won't
  reload it):
  ```bash
  sudo rm /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
  ```
  To avoid this class of issue entirely, never start `socket_vmnet`
  manually with a gateway/mask that doesn't exactly match
  `socket_vmnet_gateway`/`socket_vmnet_mask` (see **Install**); prefer
  `./setup.sh --reset-network`, which always uses the tofu-configured
  values, over copying a remembered/hardcoded command.
- **`sudo` can't prompt for a password**: `qemu-up.sh`'s host-route setup
  and `setup.sh --reset-network`'s daemon restart both call `sudo` from a
  non-interactive context (a Tofu `local-exec` provisioner, or a
  backgrounded daemon). If your `sudo` timestamp isn't already cached,
  these hang or fail waiting for a password. Run `sudo -v` once in the
  same terminal right before `./setup.sh` to cache credentials for the
  duration of the run.

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
