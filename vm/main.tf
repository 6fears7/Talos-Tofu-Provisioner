
# Recreates the network previously defined manually via vpn-safe-net.xml
# (virsh net-define/net-start/net-autostart) so `tofu apply`/`tofu destroy`
# fully own its lifecycle. CGNAT range (100.64.100.0/24, not libvirt's
# default 192.168.x.x) deliberately avoids VPN split-tunnel route collisions.
resource "libvirt_network" "vpn_safe_net" {
  name      = "vpn-safe-net"
  autostart = true
  forward = {
    mode = "nat"
  }
  bridge = {
    name  = "virbr1"
    stp   = "on"
    delay = "0"
  }
  ips = [
    {
      address = "100.64.100.1"
      netmask = "255.255.255.0"
      dhcp = {
        ranges = [
          {
            start = "100.64.100.2"
            end   = "100.64.100.254"
          }
        ]
      }
    }
  ]
}

resource "libvirt_domain" "cp" {
  type        = "kvm"
  name        = "talos-control-plane"
  memory      = var.cp_memory
  memory_unit = "GiB"
  vcpu        = var.cp_cpu
  autostart   = false
  running     = true
  cpu = {
    mode = "host-passthrough"
  }
  os = {
    boot_devices = [{
      dev = "hd"
      },
      {
      dev = "cdrom" }
    ]
    type      = "hvm"
    type_arch = "x86_64"
    bios = {
      use_serial = "no"
      sm_bios = {
        mode = "host"
      }
    }

  }

  devices = {
    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "0.0.0.0"
        }
      }
    ]
    disks = [

      {
        type = "file"
        driver = {
          type    = "qcow2"
          discard = "unmap"
        }
        address = {
          type = "drive"
        }
        device = "disk"
        source = {
          file = {

            file = "/var/lib/libvirt/images/${libvirt_volume.cp.name}"
          }
        }
        target = {
          dev = "hda"
          bus = "ide"
        }
      },
      {
        type   = "file"
        device = "cdrom"
        source = {
          file = {

            file = "${var.iso_path}"
          }
        }
        target = {
          dev = "hdb"
          bus = "ide"
        }
      },

    ]
    interfaces = [
      {
        model = {
          type = "virtio"
        }
        wait_for_ip = {
          source  = "any"
          timeout = 300
        }
        source = {
          network = {
            network = libvirt_network.vpn_safe_net.name
          }
        }
      }
    ]

  }
}
resource "libvirt_volume" "cp" {
  name = "talos-disk.qcow2"
  pool = "default"
  target = {
    format = {
      type = "qcow2"
    }
  }
  capacity = (1024 * 1024 * 1024 * var.cp_capacity)

}

data "libvirt_domain_interface_addresses" "cp" {
  depends_on = [libvirt_domain.cp]

  domain = libvirt_domain.cp.name
}

output "cp_vm_ip_address" {
  depends_on  = [libvirt_domain.cp]
  description = "IP address of control plane"
  value       = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
}



resource "libvirt_domain" "worker" {
  count       = var.worker_count
  type        = "kvm"
  name        = "talos-worker-${count.index}"
  memory      = var.worker_memory
  memory_unit = "GiB"
  vcpu        = var.worker_cpu
  autostart   = false
  running     = true
  cpu = {
    mode = "host-passthrough"
  }
  os = {
    boot_devices = [{
      dev = "hd"
      },
      {
      dev = "cdrom" }
    ]
    type      = "hvm"
    type_arch = "x86_64"
    bios = {
      use_serial = "no"
      sm_bios = {
        mode = "host"
      }
    }

  }

  devices = {
    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "0.0.0.0"
        }
      }
    ]
    disks = [

      {
        type = "file"
        driver = {
          type    = "qcow2"
          discard = "unmap"
        }
        address = {
          type = "drive"
        }
        device = "disk"
        source = {
          file = {

            file = "/var/lib/libvirt/images/${libvirt_volume.worker[count.index].name}"
          }
        }
        target = {
          dev = "hda"
          bus = "ide"
        }
      },
      {
        type   = "file"
        device = "cdrom"
        source = {
          file = {

            file = "${var.iso_path}"
          }
        }
        target = {
          dev = "hdb"
          bus = "ide"
        }
      },

    ]
    interfaces = [
      {
        model = {
          type = "virtio"
        }
        wait_for_ip = {
          source  = "any"
          timeout = 300
        }
        source = {
          network = {
            network = libvirt_network.vpn_safe_net.name
          }
        }
      }
    ]

  }
}


# --- WORKER DISK VOLUMES ---
resource "libvirt_volume" "worker" {
  count = var.worker_count
  name  = "talos-worker-disk-${count.index}.qcow2"
  pool  = "default"
  target = {
    format = {
      type = "qcow2"
    }
  }
  # Assuming same capacity as CP, or define a new var.worker_capacity
  capacity = (1024 * 1024 * 1024 * var.worker_capacity)
}

data "libvirt_domain_interface_addresses" "worker" {
  depends_on = [libvirt_domain.worker]
  count      = var.worker_count
  domain     = libvirt_domain.worker[count.index].name
}

output "worker_ips" {
  description = "List of IP addresses for worker nodes"
  value       = data.libvirt_domain_interface_addresses.worker[*].interfaces[0].addrs[0].addr
}

module "talos_secrets" {
  source = "../modules/talos_secrets"
}

data "talos_machine_configuration" "cp" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr}:6443"
  machine_secrets  = module.talos_secrets.machine_secrets
}

data "talos_client_configuration" "cp" {
  cluster_name         = var.cluster_name
  client_configuration = module.talos_secrets.client_configuration
  nodes                = [data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr]
  endpoints            = [data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr]
}

resource "talos_machine_configuration_apply" "cp" {
  client_configuration        = module.talos_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp.machine_configuration
  node                        = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
  config_patches = [
    yamlencode({
      machine = {
        sysctls = {
          "vm.max_map_count" = "262144"
        }
        install = {
          disk = "/dev/sda"
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
# Apply the config change to a specific node
resource "talos_machine_bootstrap" "cp" {
  depends_on = [
    talos_machine_configuration_apply.cp
  ]
  node                 = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
  client_configuration = module.talos_secrets.client_configuration
}
# --- BOOTSTRAP THE DATA PLANE ---
data "talos_machine_configuration" "worker" {
  count            = var.worker_count
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${data.libvirt_domain_interface_addresses.worker[count.index].interfaces[0].addrs[0].addr}:6443"
  machine_secrets  = module.talos_secrets.machine_secrets
}

data "talos_client_configuration" "worker" {
  count                = var.worker_count
  cluster_name         = var.cluster_name
  client_configuration = module.talos_secrets.client_configuration
  nodes                = [data.libvirt_domain_interface_addresses.worker[count.index].interfaces[0].addrs[0].addr]
}

resource "talos_machine_configuration_apply" "worker" {
  count                       = var.worker_count
  client_configuration        = module.talos_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[count.index].machine_configuration
  node                        = data.libvirt_domain_interface_addresses.worker[count.index].interfaces[0].addrs[0].addr
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        sysctls = {
          "vm.max_map_count" = "262144"
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
  node                 = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
}

locals {
  depends_on = [libvirt_domain.cp]

  kubeconfig_raw = yamlencode({
    apiVersion = "v1",
    kind       = "Config",
    clusters = [
      {
        name = var.cluster_name,
        cluster = {
          server                     = "https://${data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr}:6443",
          certificate-authority-data = module.talos_secrets.k8s_ca_cert_b64,
        }
      }
    ],
    contexts = [
      {
        name = var.cluster_name,
        context = {
          cluster = var.cluster_name,
          user    = "admin@${var.cluster_name}",
        }
      }
    ],
    current-context = var.cluster_name,
    users = [
      {
        name = "admin@${var.cluster_name}",
        user = {
          client-certificate-data = base64encode(trimspace(module.talos_secrets.k8s_client_cert_pem)),
          client-key-data         = base64encode(trimspace(module.talos_secrets.k8s_client_key_pem)),
        }
      }
    ]
  })
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
# cluster.network.cni.name=none + cluster.proxy.disabled=true above leave
# the cluster with no CNI and no kube-proxy; Cilium is installed here in
# kube-proxy-replacement mode to provide both. Values match Sidero Labs'
# documented Talos+Cilium install (cgroup/securityContext requirements
# specific to Talos's default cgroupsv2 layout and lack of NET_ADMIN).
# talos_machine_bootstrap completing doesn't mean kube-apiserver is already
# accepting connections (etcd leader election + apiserver startup still take
# up to a couple of minutes), and helm_release has no retry of its own, so
# without this wait helm_release.cilium fails immediately with "connection
# refused" and needs a manual re-apply.
data "external" "apiserver_ready" {
  depends_on = [talos_machine_bootstrap.cp]
  program    = ["${path.module}/scripts/wait-for-apiserver.sh"]
  query = {
    host    = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
    timeout = "180"
  }
}

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
    value = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
  }
  set {
    name  = "k8sServicePort"
    value = "6443"
  }
}
