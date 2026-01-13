# Deploy Talos

- Creates 1 control plane 3 worker nodes
- Removes kube-flannel & kube-proxy and replaces with cilium
- Provision everything with [./setup.sh](./setup.sh)

## PreRequisites

- You'll need a talos ISO. The default path it's checking is `/mnt/talos/metal-amd64.iso`
