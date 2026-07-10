locals {
  # Deterministic, locally-administered MAC addresses (leading octet 02)
  # derived from the cluster/node name, so re-applies are stable.
  cp_mac = format(
    "02:%s:%s:%s:%s:%s",
    substr(md5("${var.cluster_name}-cp"), 0, 2),
    substr(md5("${var.cluster_name}-cp"), 2, 2),
    substr(md5("${var.cluster_name}-cp"), 4, 2),
    substr(md5("${var.cluster_name}-cp"), 6, 2),
    substr(md5("${var.cluster_name}-cp"), 8, 2),
  )
  worker_macs = [
    for i in range(var.worker_count) : format(
      "02:%s:%s:%s:%s:%s",
      substr(md5("${var.cluster_name}-worker-${i}"), 0, 2),
      substr(md5("${var.cluster_name}-worker-${i}"), 2, 2),
      substr(md5("${var.cluster_name}-worker-${i}"), 4, 2),
      substr(md5("${var.cluster_name}-worker-${i}"), 6, 2),
      substr(md5("${var.cluster_name}-worker-${i}"), 8, 2),
    )
  ]
}

resource "terraform_data" "cp" {
  input = {
    name                    = "talos-control-plane"
    mac                     = local.cp_mac
    cpu                     = var.cp_cpu
    memory_gib              = var.cp_memory
    disk_gib                = var.cp_capacity
    iso_path                = var.iso_path
    state_dir               = var.vm_state_dir
    firmware_code           = var.firmware_code
    firmware_vars_template  = var.firmware_vars_template
    socket_vmnet_client     = var.socket_vmnet_client
    socket_vmnet_socket     = var.socket_vmnet_socket
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/qemu-up.sh '${self.input.name}' '${self.input.mac}' '${self.input.cpu}' '${self.input.memory_gib}' '${self.input.disk_gib}' '${self.input.iso_path}' '${self.input.state_dir}' '${self.input.firmware_code}' '${self.input.firmware_vars_template}' '${self.input.socket_vmnet_client}' '${self.input.socket_vmnet_socket}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/qemu-down.sh '${self.input.name}' '${self.input.state_dir}'"
  }
}

resource "terraform_data" "worker" {
  count = var.worker_count

  input = {
    name                    = "talos-worker-${count.index}"
    mac                     = local.worker_macs[count.index]
    cpu                     = var.worker_cpu
    memory_gib              = var.worker_memory
    disk_gib                = var.worker_capacity
    iso_path                = var.iso_path
    state_dir               = var.vm_state_dir
    firmware_code           = var.firmware_code
    firmware_vars_template  = var.firmware_vars_template
    socket_vmnet_client     = var.socket_vmnet_client
    socket_vmnet_socket     = var.socket_vmnet_socket
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/qemu-up.sh '${self.input.name}' '${self.input.mac}' '${self.input.cpu}' '${self.input.memory_gib}' '${self.input.disk_gib}' '${self.input.iso_path}' '${self.input.state_dir}' '${self.input.firmware_code}' '${self.input.firmware_vars_template}' '${self.input.socket_vmnet_client}' '${self.input.socket_vmnet_socket}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/qemu-down.sh '${self.input.name}' '${self.input.state_dir}'"
  }
}

data "external" "cp_ip" {
  depends_on = [terraform_data.cp]
  program    = ["${path.module}/scripts/find-ip.sh"]
  query = {
    mac     = local.cp_mac
    timeout = "300"
  }
}

data "external" "worker_ip" {
  count      = var.worker_count
  depends_on = [terraform_data.worker]
  program    = ["${path.module}/scripts/find-ip.sh"]
  query = {
    mac     = local.worker_macs[count.index]
    timeout = "300"
  }
}

output "cp_vm_ip_address" {
  description = "IP address of control plane"
  value       = data.external.cp_ip.result.ip
}

output "worker_ips" {
  description = "List of IP addresses for worker nodes"
  value       = [for w in data.external.worker_ip : w.result.ip]
}

module "talos_secrets" {
  source = "../modules/talos_secrets"
}

data "talos_machine_configuration" "cp" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${data.external.cp_ip.result.ip}:6443"
  machine_secrets  = module.talos_secrets.machine_secrets
}

data "talos_client_configuration" "cp" {
  cluster_name         = var.cluster_name
  client_configuration = module.talos_secrets.client_configuration
  nodes                = [data.external.cp_ip.result.ip]
  endpoints            = [data.external.cp_ip.result.ip]
}

resource "talos_machine_configuration_apply" "cp" {
  client_configuration        = module.talos_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp.machine_configuration
  node                        = data.external.cp_ip.result.ip
  config_patches = [
    yamlencode({
      machine = {
        sysctls = {
          "vm.max_map_count" = "262144"
        }
        install = {
          # QEMU virtio-blk disk, unlike the Linux/libvirt IDE-attached
          # /dev/sda in vm/main.tf.
          disk = "/dev/vda"
        }
        network = {
          # socket_vmnet's gateway (handed out by macOS's bootpd as the
          # DHCP nameserver) doesn't actually run a DNS relay, unlike
          # Apple's Internet Sharing. Outbound internet access itself
          # works over vmnet's NAT (confirmed via NTP), so point directly
          # at public resolvers instead of the DHCP-provided one, which
          # refuses all DNS queries and stalls the installer image pull
          # indefinitely.
          nameservers = ["1.1.1.1", "8.8.8.8"]
        }
      }
      cluster = {
        # Talos reads cni.name/proxy.disabled from the controlplane node's
        # own config to decide whether to auto-render the built-in
        # flannel + kube-proxy manifests — setting this only on the
        # worker (as it used to be) has no effect, since workers don't
        # drive manifest generation. Disabled here so helm_release.cilium
        # below is the only CNI, with Cilium's kube-proxy replacement
        # standing in for kube-proxy.
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "cp" {
  depends_on = [
    talos_machine_configuration_apply.cp
  ]
  node                 = data.external.cp_ip.result.ip
  client_configuration = module.talos_secrets.client_configuration
}

# --- BOOTSTRAP THE DATA PLANE ---
data "talos_machine_configuration" "worker" {
  count            = var.worker_count
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${data.external.worker_ip[count.index].result.ip}:6443"
  machine_secrets  = module.talos_secrets.machine_secrets
}

data "talos_client_configuration" "worker" {
  count                = var.worker_count
  cluster_name         = var.cluster_name
  client_configuration = module.talos_secrets.client_configuration
  nodes                = [data.external.worker_ip[count.index].result.ip]
}

resource "talos_machine_configuration_apply" "worker" {
  count                       = var.worker_count
  client_configuration        = module.talos_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[count.index].machine_configuration
  node                        = data.external.worker_ip[count.index].result.ip
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/vda"
        }
        sysctls = {
          "vm.max_map_count" = "262144"
        }
        network = {
          # See the matching comment on the cp config_patches above: the
          # DHCP-provided nameserver (the socket_vmnet gateway) doesn't
          # actually serve DNS, so point at public resolvers directly.
          nameservers = ["1.1.1.1", "8.8.8.8"]
        }
      }
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ]
}

resource "talos_cluster_kubeconfig" "cp" {
  depends_on = [
    data.talos_machine_configuration.cp
  ]
  client_configuration = module.talos_secrets.client_configuration
  node                 = data.external.cp_ip.result.ip
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.cp
  sensitive = true
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.cp.talos_config
  filename = "${path.module}/talosconfig"
}

# --- CNI ---
# talos_machine_bootstrap completing doesn't mean kube-apiserver is already
# accepting connections (etcd leader election + apiserver startup still take
# up to a couple of minutes), and helm_release has no retry of its own, so
# without this wait helm_release.cilium fails immediately with "connection
# refused" and needs a manual re-apply.
data "external" "apiserver_ready" {
  depends_on = [talos_machine_bootstrap.cp]
  program    = ["${path.module}/scripts/wait-for-apiserver.sh"]
  query = {
    host    = data.external.cp_ip.result.ip
    timeout = "180"
  }
}

# cluster.network.cni.name=none + cluster.proxy.disabled=true above leave
# the cluster with no CNI and no kube-proxy; Cilium is installed here in
# kube-proxy-replacement mode to provide both. Values match Sidero Labs'
# documented Talos+Cilium install (cgroup/securityContext requirements
# specific to Talos's default cgroupsv2 layout and lack of NET_ADMIN).
resource "helm_release" "cilium" {
  depends_on = [talos_machine_bootstrap.cp, data.external.apiserver_ready]

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }
  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }
  set {
    name  = "securityContext.capabilities.ciliumAgent"
    value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
  }
  set {
    name  = "securityContext.capabilities.cleanCiliumState"
    value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
  }
  set {
    name  = "cgroup.autoMount.enabled"
    value = "false"
  }
  set {
    name  = "cgroup.hostRoot"
    value = "/sys/fs/cgroup"
  }
  set {
    name  = "k8sServiceHost"
    value = data.external.cp_ip.result.ip
  }
  set {
    name  = "k8sServicePort"
    value = "6443"
  }
}
