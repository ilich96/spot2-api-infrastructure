terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-west-2"
}

resource "aws_ecr_repository" "spot2" {
  name = var.ecr_name
  image_tag_mutability = "MUTABLE"
}
