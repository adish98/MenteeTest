resource "aws_ecs_cluster" "app" {
  name = var.name
}

# No task execution role: the exam permissions boundary blocks all IAM writes.
# Without one, Fargate can only pull public images and cannot use the awslogs
# driver, so the image is hosted publicly on GHCR and container logs are not sent
# to CloudWatch.
resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # Hardened container: non-root user, read-only root filesystem, all Linux
  # capabilities dropped, and an init process to reap zombie processes.
  container_definitions = jsonencode([{
    name                   = var.name
    image                  = var.image_uri
    essential              = true
    user                   = "10001:10001"
    readonlyRootFilesystem = true
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    environment = [{
      name  = "PYTHONDONTWRITEBYTECODE"
      value = "1"
    }]
    linuxParameters = {
      initProcessEnabled = true
      capabilities = {
        add  = []
        drop = ["ALL"]
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name                               = var.name
  cluster                            = aws_ecs_cluster.app.id
  task_definition                    = aws_ecs_task_definition.app.arn
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = false
  propagate_tags                     = "SERVICE"
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60
  wait_for_steady_state              = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.name
    container_port   = 8080
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_lb_listener.http,
    aws_route_table_association.public,
  ]
}
