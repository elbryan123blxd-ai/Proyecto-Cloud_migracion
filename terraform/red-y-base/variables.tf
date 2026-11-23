variable "expected_account_id" {
  description = "Proyecto AWS permitido; evita desplegar por error en otro proyecto."
  type        = string
  default     = "519119252721"
}

variable "environment" {
  description = "Entorno independiente; main es la rama de preprod."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "preprod", "prod"], var.environment)
    error_message = "Usar dev, preprod o prod."
  }
}

variable "subredes_datos_cidr" {
  description = "Dos privadas exclusivas de RDS, sin rutas a Internet ni endpoints."
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
  validation {
    condition     = length(var.subredes_datos_cidr) == 2
    error_message = "Se requieren dos subredes de datos, una por AZ."
  }
}

variable "db_multi_az" {
  description = "Standby RDS Multi-AZ; activar solo para la prueba correspondiente."
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "Rango de IPs de toda la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subredes_publicas_cidr" {
  description = "Una por AZ. Ahi vive el ALB -- unico lugar con salida/entrada directa a Internet"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
  validation {
    condition     = length(var.subredes_publicas_cidr) == 2
    error_message = "Se requieren dos subredes publicas."
  }
}

variable "subredes_privadas_cidr" {
  description = "Dos privadas de aplicacion: GoTrue, PostgREST y ENI de endpoints; RDS va en datos."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
  validation {
    condition     = length(var.subredes_privadas_cidr) == 2
    error_message = "Se requieren dos subredes de aplicacion."
  }
}

variable "db_instance_class" {
  description = "Clase RDS inicial de laboratorio; disponibilidad y capacidad por validar en el proyecto nuevo."
  type        = string
  default     = "db.t4g.micro"
}
