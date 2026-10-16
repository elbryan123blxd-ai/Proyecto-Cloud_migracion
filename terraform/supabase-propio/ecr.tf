# =============================================================================
# ECR -- copia privada de las imagenes oficiales de GoTrue y PostgREST.
#
# Por que no tirar directo de Docker Hub: las tareas de Fargate viven en
# subred PRIVADA, sin NAT Gateway ni Internet Gateway en su tabla de rutas
# (ver network.tf de Fase 1). El unico camino que tienen para bajar una
# imagen de contenedor es el VPC Endpoint de ECR, ya preparado desde Fase 1.
# Docker Hub queda, a proposito, inalcanzable desde ahi.
#
# Terraform SOLO crea el repositorio (la "estanteria" vacia). Subir la
# imagen (docker pull de la oficial -> tag -> push aca) es un paso manual,
# fuera de Terraform -- ver README de este modulo para el comando exacto.
# =============================================================================

resource "aws_ecr_repository" "gotrue" {
  name                 = "academia-premier/gotrue"
  image_tag_mutability = "MUTABLE" # permite re-subir "latest" sin crear un repo nuevo cada vez

  image_scanning_configuration {
    scan_on_push = true # gratis, Amazon Inspector basico -- avisa si la imagen oficial trae una CVE conocida
  }

  tags = { Name = "academia-premier-ecr-gotrue" }
}

resource "aws_ecr_repository" "postgrest" {
  name                 = "academia-premier/postgrest"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "academia-premier-ecr-postgrest" }
}

# --- Solo guarda las ultimas 5 imagenes de cada repo ------------------------
# Sin esto, cada "docker push" de prueba se acumula para siempre. ECR no
# cobra por repositorio, pero si por GB almacenado -- esto lo mantiene bajo.
locals {
  politica_ecr_ultimas_5 = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantener solo las ultimas 5 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "gotrue" {
  repository = aws_ecr_repository.gotrue.name
  policy     = local.politica_ecr_ultimas_5
}

resource "aws_ecr_lifecycle_policy" "postgrest" {
  repository = aws_ecr_repository.postgrest.name
  policy     = local.politica_ecr_ultimas_5
}
