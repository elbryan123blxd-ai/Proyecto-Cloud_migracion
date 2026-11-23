# Fase 1 del plan: Red y base. Crea la VPC, las subredes, los security
# groups, RDS PostgreSQL y el secreto de su contrasena.
#
# Backend remoto "s3" -- apunta a lo que creo el modulo bootstrap (ver
# terraform/bootstrap/). Esta es la primera pieza real de la arquitectura,
# todo lo de antes (bootstrap) era solo el "donde guardar el estado".

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Configuracion por entorno mediante init -backend-config=...; nunca reutilizar el estado viejo.
  backend "s3" {}
}

provider "aws" {
  region              = "us-east-2"
  allowed_account_ids = [var.expected_account_id]

  default_tags {
    tags = {
      project     = "academia-premier-clon"
      managedby   = "terraform"
      capa        = "red-y-base"
      environment = var.environment
    }
  }
}

locals {
  prefijo = "academia-premier-${var.environment}"
}

data "aws_availability_zones" "disponibles" {
  state = "available"
}
