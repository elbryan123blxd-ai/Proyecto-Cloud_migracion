# Fase 2 del plan: "El Supabase propio". Crea ECS Fargate (GoTrue +
# PostgREST), el ALB que los expone y el bucket S3 de archivos.
#
# Backend remoto "s3", mismo bucket que Fase 1 pero otra "key" -- cada fase
# es su propio modulo de Terraform, con su propio estado, pero comparten el
# bucket/tabla de lock creados una sola vez en terraform/bootstrap/.

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
    key            = "supabase-propio/terraform.tfstate"
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
      capa      = "supabase-propio"
    }
  }
}

# --- Lee el estado de Fase 1 (red-y-base) -----------------------------------
# Asi este modulo nunca "copia y pega" IDs de VPC, subredes o security groups
# a mano -- los toma directo del estado real de lo que ya esta aplicado.
data "terraform_remote_state" "red_y_base" {
  backend = "s3"

  config = {
    bucket = "academia-premier-tfstate-994b4178"
    key    = "red-y-base/terraform.tfstate"
    region = "us-east-2"
  }
}

# --- Lee el secreto de Aurora que ya creo Fase 1 ----------------------------
# De aca sale host/puerto/usuario/password del master para armar, mas abajo,
# las URLs de conexion de GoTrue y PostgREST -- sin repetir la password a
# mano en ningun lado de este repo.
data "aws_secretsmanager_secret_version" "aurora_credentials" {
  secret_id = data.terraform_remote_state.red_y_base.outputs.aurora_secret_arn
}

locals {
  aurora = jsondecode(data.aws_secretsmanager_secret_version.aurora_credentials.secret_string)

  vpc_id            = data.terraform_remote_state.red_y_base.outputs.vpc_id
  subredes_publicas = data.terraform_remote_state.red_y_base.outputs.subredes_publicas_ids
  subredes_privadas = data.terraform_remote_state.red_y_base.outputs.subredes_privadas_ids
  sg_servicios_id   = data.terraform_remote_state.red_y_base.outputs.sg_servicios_id
  sg_alb_id         = data.terraform_remote_state.red_y_base.outputs.sg_alb_id
}
