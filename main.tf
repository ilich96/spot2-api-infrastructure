terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.66.1"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

locals {
  vpc_cidr = "10.0.0.0/16"
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

################################################################################
# AWS Elastic Container Repository
################################################################################
resource "aws_ecr_repository" "spot2" {
  name = var.ecr_name
  image_tag_mutability = "MUTABLE"
}

################################################################################
# AWS Elastic Container Service
################################################################################
module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws//modules/cluster"

  cluster_name = var.ecs_cluster_name

  # Capacity provider
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }
}

module "ecs_service" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = var.ecs_service_name
  cluster_arn = module.ecs_cluster.arn

  cpu    = 1024
  memory = 4096

  # Enables ECS Exec
  enable_execute_command = true

  # Container definition(s)
  container_definitions = {
    (var.container_name) = {
      cpu       = 512
      memory    = 1024
      essential = true
      image     = "${var.ecs_image_name}:v0.2.0"
      port_mappings = [
        {
          name          = var.container_name
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      enable_cloudwatch_logging = false

      linux_parameters = {
        capabilities = {
          add = []
          drop = [
            "NET_RAW"
          ]
        }
      }
      memory_reservation = 100
    }
  }

  service_connect_configuration = {
    namespace = aws_service_discovery_http_namespace.this.arn
    service = {
      client_alias = {
        port     = var.container_port
        dns_name = var.container_name
      }
      port_name      = var.container_name
      discovery_name = var.container_name
    }
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["spot2"].arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  subnet_ids = module.vpc.private_subnets
  security_group_rules = {
    alb_ingress_3000 = {
      type                     = "ingress"
      from_port                = var.container_port
      to_port                  = var.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  service_tags = {
    "ServiceTag" = "Tag on service level"
  }
}

################################################################################
# Supporting Resources
################################################################################
resource "aws_service_discovery_http_namespace" "this" {
  name        = var.aws_service_discovery_name
  description = "CloudMap namespace for ${var.aws_service_discovery_name}"
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = var.alb_name

  load_balancer_type = "application"

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  # For example only
  enable_deletion_protection = false

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  listeners = {
    ex_http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "spot2"
      }
    }
  }

  target_groups = {
    spot2 = {
      backend_protocol                  = "HTTP"
      backend_port                      = var.container_port
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.vpc_name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true
}
