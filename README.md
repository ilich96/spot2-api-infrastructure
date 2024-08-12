# Spot2 Infrastructure

## Introduction
This project sets up the necessary infrastructure for the project required by Spot2.
The infrastructure is deployed in AWS and uses the following services:
- [Amazon Elastic Container Service](https://aws.amazon.com/ecs/)
- [Amazon Elastic Container Registry](https://aws.amazon.com/ecr/)
- [AWS Glue](https://aws.amazon.com/glue/)
- [Amazon EC2](https://aws.amazon.com/ec2/)
- [Lambda](https://aws.amazon.com/lambda/)
- [Amazon S3](https://aws.amazon.com/s3/)
- [Amazon RDS](https://aws.amazon.com/rds/)
- [AWS Identity and Access Management](https://aws.amazon.com/iam/)
- [Amazon Virtual Private Cloud](https://aws.amazon.com/vpc/)
- [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)

## Architecture Diagram
![image](https://drive.google.com/uc?export=view&id=1QaQ5K2uPDhekFrqnblnu9t_Ibr_cdqY-)

## Prerequisites
- AWS CLI configured
- Terraform installed
- AWS account with necessary permissions

## Configuration
You need the following environment variables:
- TF_VAR_region
- TF_VAR_ecr_name
- TF_VAR_ecs_cluster_name
- TF_VAR_ecs_service_name
- TF_VAR_ecs_image_name
- TF_VAR_container_name
- TF_VAR_container_port
- TF_VAR_aws_service_discovery_name
- TF_VAR_alb_name
- TF_VAR_vpc_name
- TF_VAR_s3_bucket_name
- TF_VAR_rds_master_username

They are used in Terraform.

## Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/ilich96/spot2-api-infrastructure.git
   ```
   
2. Navigate to the project directory:
   ```bash
   cd spot2-api-infrastructure
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Review the planned changes::
   ```bash
   terraform plan
   ```

5. Apply the Terraform configuration:
   ```bash
   terraform apply
   ```
   
## Next steps
The infrastructure will be ready for using. But you need to make some steps manually to integrate with
the api.

- Run the `create_schema` lambda created. It creates the necessary table in RDS.
- Run the `transform-and-load-job` ETL job created. It inserts all data in the table created
previously.
