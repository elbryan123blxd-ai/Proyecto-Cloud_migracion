# =============================================================================
# Auto-scaling por CPU (target tracking) -- lo que el video final de Fase 5
# tiene que grabar en vivo reaccionando a las 3 oleadas de 7:30/7:40/7:45am
# (ver CLAUDE.md "Capacidad objetivo"). Un target por servicio: GoTrue y
# PostgREST escalan de forma independiente, porque reciben carga distinta
# (GoTrue solo en el login, PostgREST en cada pantalla).
# =============================================================================

resource "aws_appautoscaling_target" "gotrue" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.principal.name}/${aws_ecs_service.gotrue.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min_tareas
  max_capacity       = var.autoscaling_max_tareas
}

resource "aws_appautoscaling_policy" "gotrue_cpu" {
  name               = "academia-premier-gotrue-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.gotrue.service_namespace
  resource_id        = aws_appautoscaling_target.gotrue.resource_id
  scalable_dimension = aws_appautoscaling_target.gotrue.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.autoscaling_cpu_objetivo
  }
}

resource "aws_appautoscaling_target" "postgrest" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.principal.name}/${aws_ecs_service.postgrest.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min_tareas
  max_capacity       = var.autoscaling_max_tareas
}

resource "aws_appautoscaling_policy" "postgrest_cpu" {
  name               = "academia-premier-postgrest-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.postgrest.service_namespace
  resource_id        = aws_appautoscaling_target.postgrest.resource_id
  scalable_dimension = aws_appautoscaling_target.postgrest.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.autoscaling_cpu_objetivo
  }
}
