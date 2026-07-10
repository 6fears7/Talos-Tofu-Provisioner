module "bootstrap_token" {
  source = "../bootstrap_token"
}

module "trustdinfo_token" {
  source = "../bootstrap_token"
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
