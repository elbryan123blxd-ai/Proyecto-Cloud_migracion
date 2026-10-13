# Bootstrap: crea donde va a vivir el estado de TODO el resto del proyecto.
#
# Backend LOCAL a proposito ($0 costos, y porque es una paradoja guardar el
# estado de "el bucket que guarda el estado" adentro de ese mismo bucket
# antes de que exista). Una vez aplicado, el resto de los modulos usan
# backend "s3" apuntando a lo que este archivo crea.
#
# Cuenta AWS: programa "Ready Set Build", solo region us-east-2 habilitada.

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

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      project   = "academia-premier-clon"
      managedby = "terraform"
      capa      = "bootstrap"
    }
  }
}

resource "random_id" "sufijo" {
  byte_length = 4
}

# --- Bucket para el tfstate ---
resource "aws_s3_bucket" "tfstate" {
  bucket = "academia-premier-tfstate-${random_id.sufijo.hex}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Tabla para el lock, evita que dos "terraform apply" se pisen ---
resource "aws_dynamodb_table" "tflock" {
  name         = "academia-premier-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
