# vm

Terraform module that provisions a Talos Kubernetes cluster on libvirt/KVM.
Machine secrets and certificates are generated within Terraform using a
custom CA via the `tls` provider. Terraform stores state in plaintext;
treat `terraform.tfstate` as sensitive.

## Prerequisites

libvirt/KVM installed and running. From this directory, run `terraform init`
to pull down the required providers.

## Usage

```bash
terraform apply -var cluster_name=talos
```

`cluster_name` is required. Override other variables with `-var` or a
varsfile passed via `-var-file`.

```bash
terraform destroy
```

Export the kubeconfig and talosconfig:

```bash
terraform output -raw kubeconfig > kubeconfig
terraform output -raw talosconfig > talosconfig
```

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                               | Version       |
| ------------------------------------------------------------------ | ------------- |
| <a name="requirement_libvirt"></a> [libvirt](#requirement_libvirt) | 0.9.2         |
| <a name="requirement_random"></a> [random](#requirement_random)    | 3.5.1         |
| <a name="requirement_talos"></a> [talos](#requirement_talos)       | 0.10.0-beta.0 |
| <a name="requirement_tls"></a> [tls](#requirement_tls)             | 4.0.4         |

## Providers

| Name                                                         | Version       |
| ------------------------------------------------------------ | ------------- |
| <a name="provider_libvirt"></a> [libvirt](#provider_libvirt) | 0.7.1         |
| <a name="provider_random"></a> [random](#provider_random)    | 3.5.1         |
| <a name="provider_talos"></a> [talos](#provider_talos)       | 0.10.0-beta.0 |
| <a name="provider_tls"></a> [tls](#provider_tls)             | 4.0.4         |

## Modules

| Name                                                                                | Source                    | Version |
| ----------------------------------------------------------------------------------- | ------------------------- | ------- |
| <a name="module_bootstrap_token"></a> [bootstrap_token](#module_bootstrap_token)    | ./modules/bootstrap_token | n/a     |
| <a name="module_trustdinfo_token"></a> [trustdinfo_token](#module_trustdinfo_token) | ./modules/bootstrap_token | n/a     |

## Resources

| Name                                                                                                                                                        | Type        |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| [libvirt_domain.cp](https://registry.terraform.io/providers/dmacvicar/libvirt/0.7.1/docs/resources/domain)                                                  | resource    |
| [libvirt_volume.cp](https://registry.terraform.io/providers/dmacvicar/libvirt/0.7.1/docs/resources/volume)                                                  | resource    |
| [random_id.cluster_id](https://registry.terraform.io/providers/hashicorp/random/3.5.1/docs/resources/id)                                                    | resource    |
| [random_id.cluster_secret](https://registry.terraform.io/providers/hashicorp/random/3.5.1/docs/resources/id)                                                | resource    |
| [random_id.secretbox_encryption_secret](https://registry.terraform.io/providers/hashicorp/random/3.5.1/docs/resources/id)                                   | resource    |
| [talos_machine_bootstrap.this](https://registry.terraform.io/providers/siderolabs/talos/0.10.0-beta.0/docs/resources/machine_bootstrap)                     | resource    |
| [talos_machine_configuration_apply.this](https://registry.terraform.io/providers/siderolabs/talos/0.10.0-beta.0/docs/resources/machine_configuration_apply) | resource    |
| [tls_cert_request.client_csr](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/cert_request)                                      | resource    |
| [tls_cert_request.k8s_client_csr](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/cert_request)                                  | resource    |
| [tls_locally_signed_cert.client_cert](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/locally_signed_cert)                       | resource    |
| [tls_locally_signed_cert.k8s_client_cert](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/locally_signed_cert)                   | resource    |
| [tls_private_key.client_key](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/private_key)                                        | resource    |
| [tls_private_key.etcd_key](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/private_key)                                          | resource    |
| [tls_private_key.k8s_aggregator_key](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/private_key)                                | resource    |
| [tls_private_key.k8s_client_key](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/private_key)                                    | resource    |
| [tls_private_key.k8s_key](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/private_key)                                           | resource    |
| [tls_private_key.k8s_serviceaccount_key](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/private_key)                            | resource    |
| [tls_private_key.os_key](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/private_key)                                            | resource    |
| [tls_self_signed_cert.etcd_cert](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/self_signed_cert)                               | resource    |
| [tls_self_signed_cert.k8s_aggregator_cert](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/self_signed_cert)                     | resource    |
| [tls_self_signed_cert.k8s_cert](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/self_signed_cert)                                | resource    |
| [tls_self_signed_cert.os_cert](https://registry.terraform.io/providers/hashicorp/tls/4.0.4/docs/resources/self_signed_cert)                                 | resource    |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/0.10.0-beta.0/docs/data-sources/client_configuration)            | data source |
| [talos_machine_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/0.10.0-beta.0/docs/data-sources/machine_configuration)          | data source |

## Inputs

| Name                                                                  | Description                             | Type     | Default | Required |
| --------------------------------------------------------------------- | --------------------------------------- | -------- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster_name](#input_cluster_name) | A name to provide for the Talos cluster | `string` | n/a     |   yes    |
| <a name="input_iso_path"></a> [iso_path](#input_iso_path)             | Path to the Talos ISO                   | `string` | n/a     |   yes    |

## Outputs

| Name                                                                 | Description |
| -------------------------------------------------------------------- | ----------- |
| <a name="output_kubeconfig"></a> [kubeconfig](#output_kubeconfig)    | n/a         |
| <a name="output_talosconfig"></a> [talosconfig](#output_talosconfig) | n/a         |

<!-- END_TF_DOCS -->
