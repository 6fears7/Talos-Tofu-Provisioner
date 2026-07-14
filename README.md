# Talos-Tofu-Provisioner

⚠️ This is a personal project used to explore Tofu provisioning from scratch. There are easier methods to stand-up your Talos cluster.

Provisions a [Talos Linux](https://www.talos.dev/) Kubernetes cluster with
OpenTofu. It brings up the VMs, bootstraps the cluster, installs Cilium, and
hands you a kubeconfig. Supports Linux & Apple Silicon

## Architecture

| Component         | Linux ([vm/](vm/)) | macOS ([vm-macos/](vm-macos/))           |
| ------------------ | ------------------- | ----------------------------------------- |
| OS                 | Talos Linux          | Talos Linux                               |
| Kubernetes distro  | Talos                | Talos                                     |
| CNI                | Cilium               | Cilium                                    |
| Virtualization     | libvirt              | QEMU                                      |
| Accelerator        | KVM                  | Apple Hypervisor.framework (HVF)          |
| Networking         | libvirt NAT (`vpn-safe-net`, Tofu-managed) | `socket_vmnet` + `vmnet.framework` |

## Prerequisites

- [`tofu`](https://opentofu.org/docs/intro/install/),
- `jq`
- Talos ISO for the target architecture (amd64 for the Linux
backend's default, arm64 for macOS). Download the latest arm64 ISO from
[GitHub releases](https://github.com/siderolabs/talos/releases/latest/download/metal-arm64.iso)

- **Linux**: libvirt/KVM installed and running
- **macOS**: Homebrew `qemu` and `socket_vmnet` (`brew install qemu
  socket_vmnet`). See [vm-macos/README.md](vm-macos/README.md) for the
  daemon and host-route setup.

## Quickstart

```bash
./setup.sh --reset-network --iso-path /mnt/talos/metal-arm64.iso --worker-count 1 --clean
```

This auto-detects the backend, runs `tofu apply` in [vm/](vm/) (Linux) or
[vm-macos/](vm-macos/) (macOS), and writes a kubeconfig to `./kubeconfig`.
Backend is auto-detected from `uname -s`; override with `TARGET=linux` or
`TARGET=macos`.

| Flag              | Value    | Default                  | Backend | Description                                                               |
| ----------------- | -------- | ------------------------ | ------- | -------------------------------------------------------------------------- |
| `--iso-path`      | `<path>` | `/mnt/talos/metal-*.iso` | both    | Path to the Talos ISO (amd64 on Linux, arm64 on macOS).                    |
| `--worker-count`  | `<n>`    | `1`                      | both    | Number of worker nodes (non-negative integer).                            |
| `--cp-memory`     | `<gib>`  | `4`                      | both    | Control-plane memory in GiB.                                              |
| `--worker-memory` | `<gib>`  | `4`                      | both    | Per-worker memory in GiB.                                                 |
| `--reset-network` | —        | off                      | macOS   | Restart the `socket_vmnet` daemon before provisioning. Errors on Linux.    |
| `--clean`         | —        | off                      | macOS   | Wipe per-VM qcow2 disks and UEFI NVRAM for a clean slate. Errors on Linux. |

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
| [vm/](vm/) | OpenTofu module for the Talos cluster on Linux/libvirt/KVM (incl. the `vpn-safe-net` NAT network, `100.64.100.0/24`) |
| [vm-macos/](vm-macos/) | OpenTofu module for the Talos cluster on macOS/QEMU/HVF |
| [modules/talos_secrets](modules/talos_secrets) | Shared Talos secrets/cert generation used by both backends |
| [modules/bootstrap_token](modules/bootstrap_token) | Shared bootstrap-token generation |
| [setup.sh](setup.sh) | Detects the OS, provisions the cluster, and exports a kubeconfig |

## License

[MIT](LICENSE)
