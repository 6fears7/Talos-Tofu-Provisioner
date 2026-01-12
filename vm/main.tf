

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
            network = "default"
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
            network = "default"
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

module "bootstrap_token" {
  source = "./modules/bootstrap_token"
}

module "trustdinfo_token" {
  source = "./modules/bootstrap_token"
}

resource "random_id" "cluster_id" {
  byte_length = 32
}

resource "random_id" "cluster_secret" {
  byte_length = 32
}

resource "random_id" "secretbox_encryption_secret" {
  byte_length = 32
}

resource "tls_private_key" "etcd_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "etcd_cert" {
  private_key_pem = tls_private_key.etcd_key.private_key_pem
  subject {
    organization = "etcd"
  }
  validity_period_hours = 87600
  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "server_auth",
    "client_auth",
  ]
  is_ca_certificate = true
}

resource "tls_private_key" "k8s_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "k8s_cert" {
  private_key_pem = tls_private_key.k8s_key.private_key_pem
  subject {
    organization = "kubernetes"
  }
  validity_period_hours = 87600
  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "server_auth",
    "client_auth",
  ]
  is_ca_certificate = true
}

resource "tls_private_key" "k8s_aggregator_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "k8s_aggregator_cert" {
  private_key_pem = tls_private_key.k8s_aggregator_key.private_key_pem
  subject {
    organization = ""
  }
  validity_period_hours = 87600
  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "server_auth",
    "client_auth",
  ]
  is_ca_certificate = true
}

resource "tls_private_key" "k8s_serviceaccount_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_private_key" "os_key" {
  # talosctl gen secrets uses a ED25519 key, but the TF tls provider uses a different PEM block header
  # https://github.com/hashicorp/terraform-provider-tls/blob/66911e12898dd0b47abb11dd991abe868d8b76bd/internal/provider/types.go#L83
  # https://github.com/siderolabs/crypto/blob/c03ff58af5051acb9b56e08377200324a3ea1d5e/x509/constants.go#L18
  # whereas talos expects
  # algorithm = "ED25519"
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "os_cert" {
  private_key_pem = tls_private_key.os_key.private_key_pem
  subject {
    organization = "talos"
  }
  validity_period_hours = 87600
  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "server_auth",
    "client_auth",
  ]
  is_ca_certificate = true
}

resource "tls_private_key" "client_key" {
  algorithm = "ED25519"
}

resource "tls_cert_request" "client_csr" {
  private_key_pem = tls_private_key.client_key.private_key_pem
  subject {
    organization = "os:admin"
  }
}

resource "tls_locally_signed_cert" "client_cert" {
  ca_cert_pem           = tls_self_signed_cert.os_cert.cert_pem
  ca_private_key_pem    = tls_private_key.os_key.private_key_pem
  cert_request_pem      = tls_cert_request.client_csr.cert_request_pem
  validity_period_hours = 86400
  allowed_uses = [
    "digital_signature",
    "client_auth"
  ]
}

locals {
  machine_secrets = {
    cluster = {
      id     = random_id.cluster_id.b64_std
      secret = random_id.cluster_secret.b64_std
    }
    secrets = {
      bootstrap_token             = module.bootstrap_token.bootstrap_token
      secretbox_encryption_secret = random_id.secretbox_encryption_secret.b64_std
    }
    trustdinfo = {
      token = module.trustdinfo_token.bootstrap_token
    }
    certs = {
      etcd = {
        key  = base64encode(trimspace(tls_private_key.etcd_key.private_key_pem))
        cert = base64encode(trimspace(tls_self_signed_cert.etcd_cert.cert_pem))
      }
      k8s = {
        key  = base64encode(trimspace(tls_private_key.k8s_key.private_key_pem))
        cert = base64encode(trimspace(tls_self_signed_cert.k8s_cert.cert_pem))
      }
      k8s_aggregator = {
        key  = base64encode(trimspace(tls_private_key.k8s_aggregator_key.private_key_pem))
        cert = base64encode(trimspace(tls_self_signed_cert.k8s_aggregator_cert.cert_pem))
      }
      k8s_serviceaccount = {
        key = base64encode(trimspace(tls_private_key.k8s_serviceaccount_key.private_key_pem))
      }
      os = {
        key  = base64encode(trimspace(tls_private_key.os_key.private_key_pem))
        cert = base64encode(trimspace(tls_self_signed_cert.os_cert.cert_pem))
      }
    }
  }
  client_configuration = {
    ca_certificate     = base64encode(trimspace(tls_self_signed_cert.os_cert.cert_pem))
    client_certificate = base64encode(trimspace(tls_locally_signed_cert.client_cert.cert_pem))
    client_key         = base64encode(trimspace(tls_private_key.client_key.private_key_pem))
  }
}

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "cp" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_client_configuration" "cp" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr]
}

resource "talos_machine_configuration_apply" "cp" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp.machine_configuration
  node                        = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
      }
    })
  ]
}
resource "talos_machine_bootstrap" "cp" {
  depends_on = [
    talos_machine_configuration_apply.cp
  ]
  node                 = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
  client_configuration = talos_machine_secrets.this.client_configuration
}
# --- BOOTSTRAP THE DATA PLANE ---
data "talos_machine_configuration" "worker" {
  count            = var.worker_count
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${data.libvirt_domain_interface_addresses.worker[count.index].interfaces[0].addrs[0].addr}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_client_configuration" "worker" {
  count                = var.worker_count
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [data.libvirt_domain_interface_addresses.worker[count.index].interfaces[0].addrs[0].addr]
}

resource "talos_machine_configuration_apply" "worker" {
  count                       = var.worker_count
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[count.index].machine_configuration
  node                        = data.libvirt_domain_interface_addresses.worker[count.index].interfaces[0].addrs[0].addr
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
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
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = data.libvirt_domain_interface_addresses.cp.interfaces[0].addrs[0].addr
}

resource "tls_private_key" "k8s_client_key" {
  algorithm = "ED25519"
}

resource "tls_cert_request" "k8s_client_csr" {
  private_key_pem = tls_private_key.k8s_client_key.private_key_pem
  subject {
    organization = "system:masters"
    common_name  = "admin"
  }
}

resource "tls_locally_signed_cert" "k8s_client_cert" {
  ca_cert_pem           = tls_self_signed_cert.k8s_cert.cert_pem
  ca_private_key_pem    = tls_private_key.k8s_key.private_key_pem
  cert_request_pem      = tls_cert_request.k8s_client_csr.cert_request_pem
  validity_period_hours = 8760
  allowed_uses = [
    "digital_signature",
    "client_auth"
  ]
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
          certificate-authority-data = local.machine_secrets.certs.k8s.cert,
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
          client-certificate-data = base64encode(trimspace(tls_locally_signed_cert.k8s_client_cert.cert_pem)),
          client-key-data         = base64encode(trimspace(tls_private_key.k8s_client_key.private_key_pem)),
        }
      }
    ]
  })
}


output "kubeconfig" {
  value     = talos_cluster_kubeconfig.cp
  sensitive = true
}
