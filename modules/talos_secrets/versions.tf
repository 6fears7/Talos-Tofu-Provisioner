terraform {
  required_providers {
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
  }
}
