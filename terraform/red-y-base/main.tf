# Fase 1 del plan: Red y base. Crea la VPC, las subredes, los security
# groups, Aurora Serverless v2 y el secreto de su contrasena.
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

  backend "s3" {
    bucket         = "academia-premier-tfstate-994b4178"
    key            = "red-y-base/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "academia-premier-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      project   = "academia-premier-clon"
      managedby = "terraform"
      capa      = "red-y-base"
    }
  }
}

data "aws_availability_zones" "disponibles" {
  state = "available"
}
