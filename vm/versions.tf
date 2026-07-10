terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.0"
    }
    helm = {
      source  = "hashicorp/helm"
      # Pinned to the last 2.x release: v3 migrated to the plugin
      # framework and changed the provider config block syntax
      # (`kubernetes { }` -> `kubernetes = { }`), which would require
      # rewriting the provider block below.
      version = "2.17.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.4"
    }
  }
}


provider "libvirt" {
  uri = "qemu:///system"
}
provider "random" {}

provider "tls" {}

provider "talos" {}

provider "helm" {
  kubernetes {
    host                   = talos_cluster_kubeconfig.cp.kubernetes_client_configuration.host
    client_certificate     = base64decode(talos_cluster_kubeconfig.cp.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.cp.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.cp.kubernetes_client_configuration.ca_certificate)
  }
}
