output "ecs_cluster_name" {
  value = aws_ecs_cluster.app.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.app.arn
}

output "application_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "ecs_task_definition_family" {
  value = aws_ecs_task_definition.app.family
}

output "ecs_container_name" {
  value = var.name
}
