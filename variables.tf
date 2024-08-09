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

variable "ecs_image_name" {
  description = "Name of the image used by ECS."
  type        = string
}

variable "container_name" {
  description = "Name of the container used by ECS."
  default     = "spot2-api-backend"
  type        = string
}

variable "container_port" {
  description = "Port of the container used by ECS."
  default     = 80
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

variable "s3_bucket_name" {
  description = "Name of the bucket used by S3."
  type        = string
}

variable "rds_master_username" {
  description = "Username for the master DB user."
  type        = string
}

variable "rds_master_password" {
  description = "Username for the master DB user."
  type        = string
}
