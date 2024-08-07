
output "ecr_name" {
  value = aws_ecr_repository.spot2.name
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.name
}
