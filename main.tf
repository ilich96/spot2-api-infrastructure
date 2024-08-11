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

      health_check = {
        command  = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/up || exit 1"]
        interval = 300
      }

      readonly_root_filesystem = false

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
        path                = "/up"
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
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 96)]

  enable_nat_gateway = true
  single_nat_gateway = true
}

################################################################################
# AWS S3
################################################################################
resource "aws_s3_bucket" "spot2" {
  bucket = var.s3_bucket_name
}

resource "aws_s3_object" "dataset" {
  bucket = aws_s3_bucket.spot2.id
  key    = "/datasets/land_uses.csv"
  source = "datasets/catastro2021_ALVARO_OBREGON.csv"

  etag = filemd5("datasets/catastro2021_ALVARO_OBREGON.csv")
}

################################################################################
# AWS Aurora
################################################################################
module "aurora_db" {
  source  = "terraform-aws-modules/rds-aurora/aws"

  name           = "spot2-aurora-db"
  database_name  = "spot2"
  engine         = "aurora-postgresql"
  engine_version = "13.7"
  instance_class = "db.t4g.medium"
  instances = {
    one = {}
  }

  vpc_id               = module.vpc.vpc_id
  db_subnet_group_name = module.vpc.database_subnet_group_name
  security_group_rules = {
    vpc_ingress = {
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      source_security_group_id = module.aurora_db.security_group_id
    }
    vpc_egress = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      ip_protocol = "-1"
      cidr_blocks   = ["0.0.0.0/0"]
    }
  }

  create_db_cluster_parameter_group      = true
  db_cluster_parameter_group_name        = "spot2"
  db_cluster_parameter_group_family      = "aurora-postgresql13"
  db_cluster_parameter_group_description = "spot2 cluster parameter group"
  db_cluster_parameter_group_parameters  = [
    {
      name         = "password_encryption"
      value        = "md5"
      apply_method = "immediate"
    }
  ]

  master_username             = var.rds_master_username
  manage_master_user_password = true

  storage_encrypted   = true
  apply_immediately   = true
  monitoring_interval = 10
  skip_final_snapshot = true

  enabled_cloudwatch_logs_exports = ["postgresql"]
}

data "archive_file" "create_schema" {
  type        = "zip"
  source_dir = "${path.module}/scripts/create_schema/"
  output_path = "create_schema.zip"
}

resource "aws_lambda_function" "create_schema" {
  filename      = "create_schema.zip"
  function_name = "create_schema"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  timeout       = 30

  vpc_config {
    subnet_ids         = module.vpc.database_subnets
    security_group_ids = [module.aurora_db.security_group_id]
  }

  environment {
    variables = {
      DB_HOST     = module.aurora_db.cluster_endpoint
      DB_PORT     = module.aurora_db.cluster_port
      DB_NAME     = module.aurora_db.cluster_database_name
      SECRET_NAME = module.aurora_db.cluster_master_user_secret[0]["secret_arn"]
    }
  }

  source_code_hash = data.archive_file.create_schema.output_base64sha256
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy_attachment" "lambda_exec_policy" {
  name       = "lambda_exec_attachment"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  roles      = [aws_iam_role.lambda_exec.name]
}

resource "aws_iam_policy_attachment" "lambda_vpc_exec_policy" {
  name       = "lambda_vpc_exec_attachment"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  roles      = [aws_iam_role.lambda_exec.name]
}

resource "aws_iam_role_policy" "lambda_secrets_policy" {
  name = "lambda_secrets_policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = module.aurora_db.cluster_master_user_secret[0]["secret_arn"]
      }
    ]
  })
}

################################################################################
# AWS Glue
################################################################################
resource "aws_glue_catalog_database" "spot2" {
  name = "spot2-database"
}

resource "aws_glue_crawler" "spot2" {
  database_name = aws_glue_catalog_database.spot2.name
  name          = "spot2-crawler"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.spot2.bucket}/datasets/"
  }

  configuration = jsonencode({
    "Version": 1.0,
    "Grouping": {
      "TableGroupingPolicy": "CombineCompatibleSchemas"
    }
  })

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_iam_role" "glue_role" {
  name = "glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "glue_role_policy" {
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.spot2.arn,
          "${aws_s3_bucket.spot2.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = [
          "glue:*",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListAllMyBuckets",
          "s3:GetBucketAcl",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeRouteTables",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcAttribute",
          "iam:ListRolePolicies",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "cloudwatch:PutMetricData",
        ]
        Resource = "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:CreateBucket"
        ],
        "Resource": [
          "arn:aws:s3:::aws-glue-*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        "Resource": [
          "arn:aws:s3:::aws-glue-*/*",
          "arn:aws:s3:::*/*aws-glue-*/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
            "s3:GetObject"
        ],
        "Resource": [
          "arn:aws:s3:::crawler-public*",
          "arn:aws:s3:::aws-glue-*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "rds-db:connect"
        ],
        Resource = "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": [
          "arn:aws:logs:*:*:*:/aws-glue/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        "Condition": {
          "ForAllValues:StringEquals": {
            "aws:TagKeys": [
              "aws-glue-service-resource"
            ]
          }
        },
        "Resource": [
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:instance/*"
        ]
      }
    ]
  })
}

data "aws_secretsmanager_secret" "aurora_password" {
  arn = module.aurora_db.cluster_master_user_secret[0]["secret_arn"]
}

data "aws_secretsmanager_secret_version" "current" {
  secret_id = data.aws_secretsmanager_secret.aurora_password.id
}

resource "aws_glue_connection" "aurora_connection" {
  name = "aurora-connection"

  connection_properties = {
    "JDBC_CONNECTION_URL" = "jdbc:postgresql://${module.aurora_db.cluster_endpoint}:${module.aurora_db.cluster_port}/${module.aurora_db.cluster_database_name}"
    "USERNAME"            = jsondecode(data.aws_secretsmanager_secret_version.current.secret_string)["username"]
    "PASSWORD"            = jsondecode(data.aws_secretsmanager_secret_version.current.secret_string)["password"]
  }

  physical_connection_requirements {
    availability_zone = local.azs[0]
    security_group_id_list = [module.aurora_db.security_group_id]
    subnet_id              = module.vpc.database_subnets[0]
  }
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.spot2.id
  key    = "/glue/transform.py"
  source = "scripts/glue_job/transform.py"

  etag = filemd5("scripts/glue_job/transform.py")
}

resource "aws_glue_job" "transform_and_load" {
  name     = "transform-and-load-job"
  role_arn = aws_iam_role.glue_role.arn
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.spot2.bucket}${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--glue_database_name"   = aws_glue_catalog_database.spot2.name
    "--glue_table_name"      = "datasets"
    "--glue_connection_name" = aws_glue_connection.aurora_connection.name
    "--aurora_table_name"    = "public.land_uses"
  }

  max_retries  = 1
  timeout      = 2880
  max_capacity = 10.0
}
