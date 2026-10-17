variable "vpc_cidr" {
  description = "Rango de IPs de toda la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subredes_publicas_cidr" {
  description = "Una por AZ. Ahi vive el ALB -- unico lugar con salida/entrada directa a Internet"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "subredes_privadas_cidr" {
  description = "Una por AZ. GoTrue, PostgREST, la base y los VPC Endpoints viven aca -- sin acceso directo desde Internet"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_instance_class" {
  description = "Tamano de la instancia RDS. db.t4g.micro se quedo sin creditos de CPU en vivo (2026-10-17, ver rds.tf) -- se intento subir a db.t4g.small, pero la cuenta 'Ready Set Build' lo rechazo con FreeTierRestrictionError: 'This instance size isn't available with free plan accounts'. Tercera restriccion confirmada de este plan (las otras dos: Aurora sin VPC propia, sin SSO). Vuelve a micro, el fix real es agregar indices (gratis) en vez de mas CPU (no permitido)."
  type        = string
  default     = "db.t4g.micro"
}
