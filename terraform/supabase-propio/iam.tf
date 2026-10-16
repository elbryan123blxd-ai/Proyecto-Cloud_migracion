# =============================================================================
# IAM para Fargate -- dos roles, con trabajos distintos:
#
# - "execution role": lo usa el AGENTE de Fargate (no tu codigo) para bajar
#   la imagen de ECR y resolver los "secrets" de la task definition ANTES
#   de que el contenedor arranque. GoTrue/PostgREST nunca ven este rol.
# - "task role": el que tendria tu codigo adentro del contenedor, por si
#   necesitara llamar a otro servicio de AWS en tiempo de ejecucion. Ninguno
#   de los dos servicios lo necesita todavia (no hablan con S3 directo) --
#   se crea igual, vacio, porque ECS lo exige como campo de la task
#   definition.
# =============================================================================

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "academia-premier-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Managed policy oficial de AWS: pull de ECR + escribir logs a CloudWatch.
resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# La managed policy de arriba NO incluye leer Secrets Manager -- eso es
# especifico de que secretos usa ESTE proyecto, se agrega a mano.
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.jwt_secret.arn,
      aws_secretsmanager_secret.authenticator.arn,
      aws_secretsmanager_secret.gotrue_database_url.arn,
      aws_secretsmanager_secret.postgrest_database_url.arn,
    ]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "leer-secretos-de-servicios"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

resource "aws_iam_role" "tarea" {
  name               = "academia-premier-ecs-tarea"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}
