output "machine_secrets" {
  value     = talos_machine_secrets.this.machine_secrets
  sensitive = true
}

output "client_configuration" {
  value     = talos_machine_secrets.this.client_configuration
  sensitive = true
}

output "k8s_ca_cert_b64" {
  description = "Base64-encoded k8s CA certificate from the hand-rolled tls CA (used by the manual kubeconfig assembly)"
  value       = local.machine_secrets.certs.k8s.cert
}

output "k8s_client_cert_pem" {
  value     = tls_locally_signed_cert.k8s_client_cert.cert_pem
  sensitive = true
}

output "k8s_client_key_pem" {
  value     = tls_private_key.k8s_client_key.private_key_pem
  sensitive = true
}
