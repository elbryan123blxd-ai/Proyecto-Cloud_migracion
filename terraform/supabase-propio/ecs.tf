data "aws_region" "actual" {}

resource "aws_ecs_cluster" "principal" {
  name = "academia-premier"

  setting {
    name  = "containerInsights"
    value = "disabled" # Container Insights tiene costo propio de CloudWatch -- de mas para el clon
  }

  tags = { Name = "academia-premier-ecs-cluster" }
}

resource "aws_cloudwatch_log_group" "gotrue" {
  name              = "/ecs/academia-premier/gotrue"
  retention_in_days = 7 # minimo que alcanza para debuggear sin acumular costo

  tags = { Name = "academia-premier-logs-gotrue" }
}

resource "aws_cloudwatch_log_group" "postgrest" {
  name              = "/ecs/academia-premier/postgrest"
  retention_in_days = 7

  tags = { Name = "academia-premier-logs-postgrest" }
}

# =============================================================================
# GoTrue -- el auth. Corre las migraciones del schema "auth" el mismo al
# arrancar (crea auth.users, auth.refresh_tokens, etc. -- el schema "auth"
# ya existe desde antes, con el stub de auth.uid() que carga db/schema.sql).
# =============================================================================

resource "aws_ecs_task_definition" "gotrue" {
  family                   = "academia-premier-gotrue"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # obligatorio con Fargate -- cada tarea tiene su propia interfaz de red (ENI)
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memoria
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.tarea.arn

  container_definitions = jsonencode([
    {
      name  = "gotrue"
      image = "${aws_ecr_repository.gotrue.repository_url}:${var.gotrue_image_tag}"

      portMappings = [{ containerPort = 9999, protocol = "tcp" }]

      environment = [
        { name = "GOTRUE_API_HOST", value = "0.0.0.0" },
        { name = "PORT", value = "9999" },
        { name = "GOTRUE_DB_DRIVER", value = "postgres" },
        # Sin dominio propio todavia (Fase 3) -- estos dos apuntan al ALB por
        # su DNS name publico, en el puerto del listener de GoTrue (8081)
        { name = "API_EXTERNAL_URL", value = "http://${aws_lb.principal.dns_name}:8081" },
        { name = "GOTRUE_SITE_URL", value = "http://${aws_lb.principal.dns_name}:8081" },
        { name = "GOTRUE_URI_ALLOW_LIST", value = "*" }, # clon de portfolio, sin frontend real todavia -- se acota en Fase 3
        { name = "GOTRUE_DISABLE_SIGNUP", value = "false" },
        { name = "GOTRUE_JWT_AUD", value = "authenticated" },
        { name = "GOTRUE_JWT_DEFAULT_GROUP_NAME", value = "authenticated" },
        { name = "GOTRUE_JWT_ADMIN_ROLE", value = "service_role" },
        { name = "GOTRUE_JWT_EXP", value = "3600" },
        # Sin servidor SMTP propio: autoconfirma el email en vez de mandar un
        # link de verificacion que nunca llegaria a ningun lado
        { name = "GOTRUE_MAILER_AUTOCONFIRM", value = tostring(var.gotrue_mailer_autoconfirm) },
        { name = "GOTRUE_EXTERNAL_EMAIL_ENABLED", value = "true" },
      ]

      secrets = [
        { name = "GOTRUE_DB_DATABASE_URL", valueFrom = aws_secretsmanager_secret.gotrue_database_url.arn },
        { name = "GOTRUE_JWT_SECRET", valueFrom = aws_secretsmanager_secret.jwt_secret.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.gotrue.name
          "awslogs-region"        = data.aws_region.actual.name
          "awslogs-stream-prefix" = "gotrue"
        }
      }
    }
  ])

  tags = { Name = "academia-premier-taskdef-gotrue" }
}

resource "aws_ecs_service" "gotrue" {
  name            = "gotrue"
  cluster         = aws_ecs_cluster.principal.id
  task_definition = aws_ecs_task_definition.gotrue.arn
  desired_count   = var.autoscaling_min_tareas
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = local.subredes_privadas
    security_groups = [local.sg_servicios_id]
    # Sin IP publica -- igual que la base, nunca es alcanzable directo desde
    # Internet. Solo recibe trafico que ya paso por el ALB (ver network.tf).
    #
    # Revertido 2026-10-16/17 el intento de moverlo a subred publica: la
    # causa real del CannotPullContainerError no era DNS privada rota, era
    # el egress de sg-servicios (solo permitia 10.0.0.0/16). ECR guarda las
    # capas de las imagenes en S3, y el Gateway Endpoint de S3 usa IPs
    # PUBLICAS como destino (solo cambia el ruteo, no el DNS) -- por eso el
    # security group las bloqueaba. Fix real: egress a la prefix list de S3
    # en network.tf, sigue en subred privada como el plan original.
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gotrue.arn
    container_name   = "gotrue"
    container_port   = 9999
  }

  # Evita que Terraform pelee con Application Auto Scaling por el numero de
  # tareas corriendo -- una vez creado el servicio, quien manda ahi es el
  # target tracking de autoscaling.tf, no el desired_count de arriba.
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.gotrue]

  tags = { Name = "academia-premier-ecs-servicio-gotrue" }
}

# =============================================================================
# PostgREST -- la API. Se conecta como el rol "authenticator" (no el master
# de Aurora), creado a mano con db/post-gotrue-roles.sql.
# =============================================================================

resource "aws_ecs_task_definition" "postgrest" {
  family                   = "academia-premier-postgrest"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memoria
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.tarea.arn

  container_definitions = jsonencode([
    {
      name  = "postgrest"
      image = "${aws_ecr_repository.postgrest.repository_url}:${var.postgrest_image_tag}"

      portMappings = [{ containerPort = 3000, protocol = "tcp" }]

      environment = [
        { name = "PGRST_DB_SCHEMAS", value = "public" }, # alcance decidido en db/schema.sql: solo el schema public
        { name = "PGRST_DB_ANON_ROLE", value = "anon" },
        { name = "PGRST_SERVER_PORT", value = "3000" },
        { name = "PGRST_DB_USE_LEGACY_GUCS", value = "false" },
      ]

      secrets = [
        { name = "PGRST_DB_URI", valueFrom = aws_secretsmanager_secret.postgrest_database_url.arn },
        { name = "PGRST_JWT_SECRET", valueFrom = aws_secretsmanager_secret.jwt_secret.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.postgrest.name
          "awslogs-region"        = data.aws_region.actual.name
          "awslogs-stream-prefix" = "postgrest"
        }
      }
    }
  ])

  tags = { Name = "academia-premier-taskdef-postgrest" }
}

resource "aws_ecs_service" "postgrest" {
  name            = "postgrest"
  cluster         = aws_ecs_cluster.principal.id
  task_definition = aws_ecs_task_definition.postgrest.arn
  desired_count   = var.autoscaling_min_tareas
  launch_type     = "FARGATE"

  network_configuration {
    # Revertido -- ver nota en el service de gotrue, mismo motivo.
    subnets         = local.subredes_privadas
    security_groups = [local.sg_servicios_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.postgrest.arn
    container_name   = "postgrest"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.postgrest]

  tags = { Name = "academia-premier-ecs-servicio-postgrest" }
}
