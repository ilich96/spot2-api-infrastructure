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

variable "ecs_service_name" {
  description = "Name of the service used by ECS."
  default     = "spot2-service"
  type        = string
}

variable "container_name" {
  description = "Name of the container used by ECS."
  default     = "ecsdemo-frontend"
  type        = string
}

variable "container_port" {
  description = "Port of the container used by ECS."
  default     = 3000
  type        = number
}

variable "aws_service_discovery_name" {
  description = "Name of the service discovery used by ECS."
  default     = "spot2-service-discovery"
  type        = string
}

variable "alb_name" {
  description = "Name of the alb used by ECS."
  default     = "spot2-alb"
  type        = string
}

variable "vpc_name" {
  description = "Name of the vpc used by ECS."
  default     = "spot2-vpc"
  type        = string
}
