
variable "iso_path" {
  description = "Path to the Talos ISO"
  type        = string
  default     = "/mnt/talos/metal-amd64.iso"
}

variable "cp_capacity" {
  description = "size of the storage volume in GB for control plane nodes (Recommended: 20)"
  type        = string
}
variable "cp_memory" {
  description = "Control plane memory allocation in GiB (Recommended: 8)"
  type        = number
}
variable "cp_cpu" {
  description = "Control plane CPU allocation (Recommended: 2)"
  type        = number
}

variable "worker_capacity" {
  description = "size of the storage volume in GB for data plane nodes (Recommended: 20)"
  type        = string
}
variable "worker_memory" {
  description = "Worker memory allocation in GiB (Recommended: 8)"
  type        = number
}
variable "worker_cpu" {
  description = "Worker CPU allocation (Recommended: 2)"
  type        = number
}

variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
}

variable "worker_count" {
  default = 3
}

