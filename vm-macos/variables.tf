variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
}

variable "iso_path" {
  description = "Path to the arm64 Talos ISO"
  type        = string
  default     = "/mnt/talos/metal-arm64.iso"
}

variable "cp_capacity" {
  description = "size of the storage volume in GB for control plane nodes (Default: 20)"
  type        = string
  default     = "20"
}
variable "cp_memory" {
  description = "Control plane memory allocation in GiB (Default: 8)"
  type        = number
  default     = 8
}
variable "cp_cpu" {
  description = "Control plane CPU allocation (Default: 2)"
  type        = number
  default     = 2
}

variable "worker_capacity" {
  description = "size of the storage volume in GB for data plane nodes (Default: 20)"
  type        = string
  default     = "20"
}
variable "worker_memory" {
  description = "Worker memory allocation in GiB (Default: 8)"
  type        = number
  default     = 8
}
variable "worker_cpu" {
  description = "Worker CPU allocation (Default: 2)"
  type        = number
  default     = 2
}

variable "worker_count" {
  default = 1
}

variable "firmware_code" {
  description = "Path to the read-only UEFI firmware code image (Homebrew qemu's edk2-aarch64-code.fd)"
  type        = string
  default     = "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
}

variable "firmware_vars_template" {
  description = "Path to the UEFI NVRAM vars template; each VM gets its own writable copy"
  type        = string
  default     = "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
}

variable "socket_vmnet_client" {
  description = "Path to the socket_vmnet_client binary (brew install socket_vmnet)"
  type        = string
  default     = "/opt/homebrew/opt/socket_vmnet/bin/socket_vmnet_client"
}

variable "socket_vmnet_socket" {
  description = "Path to the socket_vmnet daemon's listening socket. The daemon must already be running (sudo socket_vmnet --vmnet-gateway=... <this path>) before tofu apply."
  type        = string
  default     = "/opt/homebrew/var/run/socket_vmnet"
}

variable "vm_state_dir" {
  description = "Directory holding per-VM disks, NVRAM copies, and pidfiles (relative to where `tofu apply` is run, i.e. vm-macos/)"
  type        = string
  default     = "./.vms"
}

variable "cilium_version" {
  description = "Cilium Helm chart version to install as the cluster's CNI"
  type        = string
  default     = "1.19.5"
}
