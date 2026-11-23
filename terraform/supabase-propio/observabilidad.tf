# Metricas nativas: no requieren agente ni Container Insights.
# Las alarmas son opt-in: sus umbrales y ventanas se deciden con una baseline.
variable "observabilidad_dashboard" {
  description = "Crear dashboard CloudWatch (puede generar cargos)"
  type        = bool
  default     = true
}

variable "observabilidad_sns_arn" {
  description = "Topic SNS existente en us-east-2, con permisos para CloudWatch; null = sin notificaciones"
  type        = string
  default     = null
  validation {
    condition     = var.observabilidad_sns_arn == null ? true : can(regex("^arn:aws:sns:us-east-2:[0-9]{12}:.+$", var.observabilidad_sns_arn))
    error_message = "Usa un ARN SNS de us-east-2 o null."
  }
}

variable "observabilidad_alarmas" {
  description = "Alarmas elegidas con umbral, periodo y evaluacion explicitos; ver docs/OBSERVABILIDAD.md"
  type = map(object({
    threshold           = number
    period              = number
    evaluation_periods  = number
    datapoints_to_alarm = number
  }))
  default = {}
  validation {
    condition = alltrue([
      for nombre, alarma in var.observabilidad_alarmas :
      contains(["gotrue_cpu", "gotrue_memoria", "postgrest_cpu", "postgrest_memoria", "gotrue_unhealthy", "postgrest_unhealthy", "db_cpu", "db_memoria", "db_almacenamiento"], nombre) &&
      alarma.threshold >= 0 && alarma.period >= 60 && alarma.period % 60 == 0 &&
      alarma.evaluation_periods >= 1 && floor(alarma.evaluation_periods) == alarma.evaluation_periods &&
      alarma.datapoints_to_alarm >= 1 && floor(alarma.datapoints_to_alarm) == alarma.datapoints_to_alarm &&
      alarma.datapoints_to_alarm <= alarma.evaluation_periods
    ])
    error_message = "Nombre de alarma desconocido o ventana invalida: period multiplo de 60; 1 <= M <= N enteros."
  }
}

locals {
  observabilidad_servicios = {
    gotrue    = aws_ecs_service.gotrue.name
    postgrest = aws_ecs_service.postgrest.name
  }
  observabilidad_targets = {
    gotrue    = aws_lb_target_group.gotrue.arn_suffix
    postgrest = aws_lb_target_group.postgrest.arn_suffix
  }
  observabilidad_db = data.terraform_remote_state.red_y_base.outputs.db_instance_id
  observabilidad_catalogo = merge(
    merge([for nombre, servicio in local.observabilidad_servicios : {
      for sufijo, metrica in { cpu = "CPUUtilization", memoria = "MemoryUtilization" } :
      "${nombre}_${sufijo}" => {
        namespace  = "AWS/ECS", metric = metrica, statistic = "Average",
        dimensions = { ClusterName = aws_ecs_cluster.principal.name, ServiceName = servicio },
        comparison = "GreaterThanThreshold", missing = "missing"
      }
    }]...),
    { for nombre, target in local.observabilidad_targets : "${nombre}_unhealthy" => {
      namespace  = "AWS/ApplicationELB", metric = "UnHealthyHostCount", statistic = "Maximum",
      dimensions = { LoadBalancer = aws_lb.principal.arn_suffix, TargetGroup = target },
      comparison = "GreaterThanOrEqualToThreshold", missing = "missing"
    } },
    { for nombre, metrica in { cpu = "CPUUtilization", memoria = "FreeableMemory", almacenamiento = "FreeStorageSpace" } : "db_${nombre}" => {
      namespace                    = "AWS/RDS", metric = metrica, statistic = nombre == "cpu" ? "Average" : "Minimum",
      dimensions                   = { DBInstanceIdentifier = local.observabilidad_db },
      comparison                   = nombre == "cpu" ? "GreaterThanThreshold" : "LessThanThreshold", missing = "missing"
    } }
  )
}

resource "aws_cloudwatch_metric_alarm" "operacion" {
  for_each = var.observabilidad_alarmas

  alarm_name          = "${local.prefijo}-${each.key}"
  alarm_description   = "Replica sintetica. Runbooks: docs/OBSERVABILIDAD.md. Validar baseline y missing data."
  namespace           = local.observabilidad_catalogo[each.key].namespace
  metric_name         = local.observabilidad_catalogo[each.key].metric
  dimensions          = local.observabilidad_catalogo[each.key].dimensions
  statistic           = local.observabilidad_catalogo[each.key].statistic
  comparison_operator = local.observabilidad_catalogo[each.key].comparison
  treat_missing_data  = local.observabilidad_catalogo[each.key].missing
  threshold           = each.value.threshold
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  alarm_actions       = var.observabilidad_sns_arn == null ? [] : [var.observabilidad_sns_arn]
  ok_actions          = var.observabilidad_sns_arn == null ? [] : [var.observabilidad_sns_arn]
}

resource "aws_cloudwatch_dashboard" "operacion" {
  count          = var.observabilidad_dashboard ? 1 : 0
  dashboard_name = "${local.prefijo}-replica"
  dashboard_body = jsonencode({
    start = "-PT8H", periodOverride = "inherit",
    widgets = concat(
      [{ type = "text", x = 0, y = 0, width = 24, height = 2, properties = {
        markdown = "# Academia Premier — replica con datos sinteticos\nMetricas nativas. Sin prueba de capacidad ni SLO certificado. Runbooks: docs/OBSERVABILIDAD.md."
      } }],
      length(var.observabilidad_alarmas) > 0 ? [{ type = "alarm", x = 0, y = 2, width = 24, height = 3, properties = {
        title = "Estado de alarmas", alarms = [for alarma in aws_cloudwatch_metric_alarm.operacion : alarma.arn]
      } }] : [],
      [for indice, nombre in ["gotrue", "postgrest"] : {
        type = "metric", x = indice * 12, y = 5, width = 12, height = 6,
        properties = {
          title  = "${nombre}: CPU y memoria (%)", region = data.aws_region.actual.name,
          period = 60, stat = "Average", view = "timeSeries",
          metrics = [for metrica in ["CPUUtilization", "MemoryUtilization"] :
            ["AWS/ECS", metrica, "ClusterName", aws_ecs_cluster.principal.name, "ServiceName", local.observabilidad_servicios[nombre]]
          ]
        }
      }],
      [for indice, nombre in ["gotrue", "postgrest"] : {
        type = "metric", x = indice * 12, y = 11, width = 12, height = 6,
        properties = {
          title   = "${nombre}: latencia origen p95 (s)", region = data.aws_region.actual.name,
          period  = 60, stat = "p95", view = "timeSeries",
          metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.principal.arn_suffix, "TargetGroup", local.observabilidad_targets[nombre]]]
        }
      }],
      [{ type = "metric", x = 0, y = 17, width = 12, height = 6, properties = {
        title  = "ALB: solicitudes y errores 5xx (conteos)", region = data.aws_region.actual.name,
        period = 60, stat = "Sum", view = "timeSeries",
        metrics = [for metrica in ["RequestCount", "HTTPCode_ELB_5XX_Count", "HTTPCode_Target_5XX_Count"] :
          ["AWS/ApplicationELB", metrica, "LoadBalancer", aws_lb.principal.arn_suffix]
        ]
        } }, { type = "metric", x = 12, y = 17, width = 12, height = 6, properties = {
        title  = "Targets saludables por servicio (minimo)", region = data.aws_region.actual.name,
        period = 60, stat = "Minimum", view = "timeSeries",
        metrics = [for nombre in ["gotrue", "postgrest"] :
          ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.principal.arn_suffix, "TargetGroup", local.observabilidad_targets[nombre]]
        ]
      } }],
      [for indice, grupo in [
        { title = "RDS: CPU (%)", metrics = ["CPUUtilization"] },
        { title = "RDS: memoria y almacenamiento libres (bytes)", metrics = ["FreeableMemory", "FreeStorageSpace"] },
        { title = "RDS: conexiones", metrics = ["DatabaseConnections"] },
        { title = "RDS T4g: creditos (revisar Unlimited antes de concluir throttling)", metrics = ["CPUCreditBalance", "CPUSurplusCreditBalance", "CPUSurplusCreditsCharged"] }
        ] : {
        type = "metric", x = (indice % 2) * 12, y = 23 + floor(indice / 2) * 6, width = 12, height = 6,
        properties = {
          title   = grupo.title, region = data.aws_region.actual.name, period = 300, stat = "Average", view = "timeSeries",
          metrics = [for metrica in grupo.metrics : ["AWS/RDS", metrica, "DBInstanceIdentifier", local.observabilidad_db]]
        }
      }]
    )
  })
}

output "observabilidad_dashboard_nombre" {
  value = try(aws_cloudwatch_dashboard.operacion[0].dashboard_name, null)
}
