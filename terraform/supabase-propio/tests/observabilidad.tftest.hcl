# Suite verificada con Terraform 1.16.5. No consulta ni modifica AWS.
variables {
  tfstate_bucket = "synthetic-new-project-tfstate"
}

mock_provider "aws" {
  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = "{\"username\":\"demo\",\"password\":\"synthetic-only\",\"host\":\"db.example.internal\",\"port\":5432,\"dbname\":\"demo\"}"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-2" }
  }
  mock_data "aws_cloudfront_cache_policy" {
    defaults = { id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" }
  }
  mock_data "aws_cloudfront_origin_request_policy" {
    defaults = { id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" }
  }
}

mock_provider "random" {}

override_resource {
  override_during = plan
  target          = aws_lb.principal
  values = {
    arn_suffix = "app/academia-premier-alb/1234567890123456"
    arn        = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/app/academia-premier-alb/1234567890123456"
    dns_name   = "demo.us-east-2.elb.amazonaws.com"
  }
}

override_resource {
  override_during = plan
  target          = aws_lb_target_group.gotrue
  values = {
    arn_suffix = "targetgroup/gotrue/1234567890123456"
    arn        = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/gotrue/1234567890123456"
  }
}

override_resource {
  override_during = plan
  target          = aws_lb_target_group.postgrest
  values = {
    arn_suffix = "targetgroup/postgrest/1234567890123456"
    arn        = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/postgrest/1234567890123456"
  }
}

override_data {
  target = data.terraform_remote_state.red_y_base
  values = {
    outputs = {
      environment           = "dev"
      project_account_id    = "519119252721"
      vpc_id                = "vpc-12345678"
      subredes_publicas_ids = ["subnet-11111111", "subnet-22222222"]
      subredes_privadas_ids = ["subnet-33333333", "subnet-44444444"]
      sg_servicios_id       = "sg-11111111"
      sg_alb_id             = "sg-22222222"
      aurora_secret_arn     = "arn:aws:secretsmanager:us-east-2:123456789012:secret:demo-abcdef"
      db_instance_id        = "academia-premier-db"
    }
  }
}

run "sin_alarmas_implicitas" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.operacion) == 0
    error_message = "No deben crearse alarmas con umbrales o destinatarios implicitos."
  }

  assert {
    condition = anytrue([
      for widget in jsondecode(aws_cloudwatch_dashboard.operacion[0].dashboard_body).widgets :
      try(widget.properties.stat == "p95" && widget.properties.metrics[0][5] == "targetgroup/gotrue/1234567890123456", false)
    ])
    error_message = "El dashboard debe ser JSON valido y medir p95 sobre el target group real de GoTrue."
  }
}

run "dashboard_desactivable" {
  command = plan
  variables {
    observabilidad_dashboard = false
  }
  assert {
    condition     = length(aws_cloudwatch_dashboard.operacion) == 0
    error_message = "La opcion de costo debe permitir no crear dashboard."
  }
}

run "alarmas_dimensiones_y_unidades" {
  command = plan
  variables {
    observabilidad_alarmas = {
      db_memoria = {
        threshold = 104857600, period = 60, evaluation_periods = 3, datapoints_to_alarm = 2
      }
      gotrue_unhealthy = {
        threshold = 1, period = 60, evaluation_periods = 3, datapoints_to_alarm = 2
      }
    }
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.operacion["db_memoria"].dimensions.DBInstanceIdentifier == "academia-premier-db" &&
      aws_cloudwatch_metric_alarm.operacion["db_memoria"].metric_name == "FreeableMemory" &&
      aws_cloudwatch_metric_alarm.operacion["db_memoria"].comparison_operator == "LessThanThreshold"
    )
    error_message = "Memoria libre debe evaluar bytes hacia abajo sobre la instancia RDS correcta."
  }
  assert {
    condition = (
      aws_cloudwatch_metric_alarm.operacion["gotrue_unhealthy"].statistic == "Maximum" &&
      aws_cloudwatch_metric_alarm.operacion["gotrue_unhealthy"].datapoints_to_alarm == 2 &&
      length(aws_cloudwatch_metric_alarm.operacion["gotrue_unhealthy"].alarm_actions) == 0
    )
    error_message = "Targets no saludables deben conservar M-de-N y no inventar un destino SNS."
  }
}

run "rechazar_ventana_invalida" {
  command = plan
  variables {
    observabilidad_alarmas = {
      db_cpu = {
        threshold = 80, period = 60, evaluation_periods = 2, datapoints_to_alarm = 3
      }
    }
  }
  expect_failures = [var.observabilidad_alarmas]
}

run "rechazar_estado_otro_entorno" {
  command = plan
  override_data {
    target = data.terraform_remote_state.red_y_base
    values = {
      outputs = {
        environment           = "prod"
        project_account_id    = "519119252721"
        vpc_id                = "vpc-12345678"
        subredes_publicas_ids = ["subnet-11111111", "subnet-22222222"]
        subredes_privadas_ids = ["subnet-33333333", "subnet-44444444"]
        sg_servicios_id       = "sg-11111111"
        sg_alb_id             = "sg-22222222"
        aurora_secret_arn     = "arn:aws:secretsmanager:us-east-2:519119252721:secret:demo-abcdef"
        db_instance_id        = "academia-premier-prod-db"
      }
    }
  }
  expect_failures = [data.terraform_remote_state.red_y_base]
}

run "rechazar_bucket_historico" {
  command = plan
  variables {
    tfstate_bucket = "academia-premier-tfstate-994b4178"
  }
  expect_failures = [var.tfstate_bucket]
}
