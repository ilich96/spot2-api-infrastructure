variable "region" {
  description = "The AWS region to use."
  default     = "us-west-2"
  type        = string
}

variable "ecr_name" {
  description = "Name of the Elastic Container Repository."
  default     = "spot2"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  default     = "spot2-cluster"
  type        = string
}
