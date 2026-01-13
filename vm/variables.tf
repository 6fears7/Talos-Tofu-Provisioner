
variable "iso_path" {
  description = "Path to the Talos ISO"
  type        = string
  default     = "/mnt/talos/metal-amd64.iso"
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

variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
}

variable "worker_count" {
  default = 3
}

