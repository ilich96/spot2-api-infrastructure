variable "ecr_name" {
  description = "Name of the ecr. Must be unique."
  default     = "spot2"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  default     = "spot2-cluster"
  type        = string
}
