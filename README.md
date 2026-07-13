# Talos-Tofu-Provisioner

⚠️ This is a personal project used to explore Tofu provisioning from scratch. There are easier methods to stand-up your Talos cluster.

Provisions a [Talos Linux](https://www.talos.dev/) Kubernetes cluster with
OpenTofu. It brings up the VMs, bootstraps the cluster, installs Cilium, and
hands you a kubeconfig. Two manual backends auto-detected from `uname -s`:

- **Linux** ([vm/](vm/)) — libvirt/KVM.
- **macOS / Apple Silicon** ([vm-macos/](vm-macos/)) — QEMU accelerated by
  Apple's Hypervisor.framework (HVF), networked via `vmnet.framework`, no
  libvirt/KVM involved.

## Install

Common to both backends: [`tofu`](https://opentofu.org/docs/intro/install/),
`jq`, and a Talos ISO for the target architecture (amd64 for the Linux
backend's default, arm64 for macOS). Download the latest arm64 ISO from
[GitHub releases](https://github.com/siderolabs/talos/releases/latest/download/metal-arm64.iso),
or build a custom image (e.g. with extra system extensions) via the
[Image Factory](https://factory.talos.dev/).

- **Linux**: libvirt/KVM installed and running, and the `vpn-safe-net`
  libvirt network defined and running:
  ```bash
  virsh net-define vm/vpn-safe-net.xml
  virsh net-start vpn-safe-net
  virsh net-autostart vpn-safe-net
  ```
- **macOS**: Homebrew `qemu` and `socket_vmnet` (`brew install qemu
  socket_vmnet`). See [vm-macos/README.md](vm-macos/README.md) for the
  daemon and host-route setup.

## Quickstart

```bash
./setup.sh --reset-network --iso-path /mnt/talos/metal-arm64.iso --worker-count 1
```

This auto-detects the backend, runs `tofu apply` in [vm/](vm/) (Linux) or
[vm-macos/](vm-macos/) (macOS), and writes a kubeconfig to `./kubeconfig`.
Override the backend with `TARGET=linux` or `TARGET=macos`. On macOS,
`./setup.sh --reset-network` restarts the `socket_vmnet` daemon before
provisioning — use it if VMs from a prior run became unreachable (see
[vm-macos/README.md](vm-macos/README.md)). `./setup.sh --iso-path
/path/to/metal-arm64.iso` overrides the `iso_path` tofu variable if your
ISO isn't at the module's default path. `--cp-memory <gib>` /
`--worker-memory <gib>` override the 4GiB-per-node default (also
`cp_memory`/`worker_memory` if applying manually); on macOS, setup.sh
refuses to proceed if `cp_memory + worker_memory * worker_count` would
exceed 80% of host RAM, since an over-committed host hangs a VM mid-boot
instead of failing cleanly.

On macOS, `tofu destroy` deliberately leaves the per-VM qcow2 disks and
UEFI NVRAM in `vm-macos/.vms/` (mirroring `libvirt_volume` surviving a
domain destroy). Because those disks are reused and booted before the
ISO, a destroy→apply cycle reboots the *previous* cluster's Talos install
under freshly generated machine secrets, which can stop nodes from
joining. Pass `--clean` to wipe those disks/NVRAM first for a true clean
slate: `./setup.sh --clean --reset-network --iso-path ... --worker-count 2`.

Or provision manually:

```bash
cd vm       # or vm-macos on Apple Silicon
tofu init
tofu apply -var cluster_name=talos
tofu output kubeconfig       # cluster kubeconfig
tofu output -raw talosconfig # talosctl client config
```

`cluster_name` is required and has no default; see
[vm/variables.tf](vm/variables.tf) / [vm-macos/variables.tf](vm-macos/variables.tf)
for all other tunables (node counts, CPU, memory, disk size).

Result: 1 control-plane + N worker nodes (default 1). Talos machine
secrets and certificates are generated entirely within OpenTofu using the
`tls` provider (no external `talosctl gen secrets` step required), shared
by both backends via [modules/talos_secrets](modules/talos_secrets).
**OpenTofu state stores these secrets in plaintext — treat
`terraform.tfstate` as sensitive.** [Cilium](https://cilium.io/) is
installed as the cluster's CNI via Terraform's `helm` provider
(`helm_release.cilium`), in kube-proxy replacement mode — Talos ships with
`cni.name=none` and `proxy.disabled=true` so Cilium is the only CNI/proxy
in play. Override the chart version with the `cilium_version` variable.

Once the cluster is up, see
[Educates-Examples](https://github.com/6fears7/Educates-Examples) for
example workshops/workloads to deploy on top of it.

## Teardown

```bash
cd vm       # or vm-macos
tofu destroy
```

## Folder layout

| Path | Purpose |
|------|---------|
| [vm/](vm/) | OpenTofu module for the Talos cluster on Linux/libvirt/KVM |
| [vm/vpn-safe-net.xml](vm/vpn-safe-net.xml) | libvirt NAT network definition (`100.64.100.0/24`), Linux backend only |
| [vm-macos/](vm-macos/) | OpenTofu module for the Talos cluster on macOS/QEMU/HVF |
| [modules/talos_secrets](modules/talos_secrets) | Shared Talos secrets/cert generation used by both backends |
| [modules/bootstrap_token](modules/bootstrap_token) | Shared bootstrap-token generation |
| [setup.sh](setup.sh) | Detects the OS, provisions the cluster, and exports a kubeconfig |

## License

[MIT](LICENSE)
