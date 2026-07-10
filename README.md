# Talos-Tofu-Provisioner

Provisions a [Talos Linux](https://www.talos.dev/) Kubernetes cluster on
libvirt/KVM using OpenTofu. It brings up the VMs, bootstraps the cluster,
and hands you a kubeconfig.

## Outputs

- 1 control-plane + N worker nodes (default 3) as libvirt KVM domains.
- Talos machine secrets and certificates are generated entirely within
  OpenTofu using the `tls` provider (no external `talosctl gen secrets`
  step required). Note: OpenTofu state stores these secrets in plaintext;
  see [vm/README.md](vm/README.md) for details and treat `terraform.tfstate`
  as sensitive.
- The cluster ships with `cni.name=none` and `proxy.disabled=true`. It is
  intentionally left bare; no CNI or workloads are installed.

## Prerequisites

- libvirt/KVM installed and running.
- [`tofu`](https://opentofu.org/docs/intro/install/), `jq`.
- A Talos ISO. Default path is `/mnt/talos/metal-amd64.iso`, override with
  the `iso_path` variable.
- The `vpn-safe-net` libvirt network defined and running:
  ```bash
  virsh net-define vpn-safe-net.xml
  virsh net-start vpn-safe-net
  virsh net-autostart vpn-safe-net
  ```

## Usage

```bash
./setup.sh
```

This runs `tofu apply` in [vm/](vm/) and writes a kubeconfig to
`./kubeconfig`.

Or provision manually:

```bash
cd vm
tofu init
tofu apply -var cluster_name=talos
tofu output kubeconfig       # cluster kubeconfig
tofu output -raw talosconfig # talosctl client config
```

`cluster_name` is required and has no default; see [vm/variables.tf](vm/variables.tf)
for all other tunables (node counts, CPU, memory, disk size).

## Repo layout

| Path | Purpose |
|------|---------|
| [vm/](vm/) | OpenTofu module for the Talos cluster on libvirt |
| [vpn-safe-net.xml](vpn-safe-net.xml) | libvirt NAT network definition (`100.64.100.0/24`) |
| [setup.sh](setup.sh) | Provisions the cluster and exports a kubeconfig |

## Teardown

```bash
cd vm
tofu destroy
```

## License

[MIT](LICENSE)
