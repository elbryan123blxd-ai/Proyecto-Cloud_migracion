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
  description = "Tamano de la instancia RDS. db.t4g.micro se quedo sin creditos de CPU en vivo (2026-10-17, probando Fase 3 con el dashboard real: CPUCreditBalance en 0, CPUUtilization pegado al 99%, PostgREST tirando 'Timed out acquiring connection from pool') -- subida a db.t4g.small para tener margen durante las pruebas. Para produccion real con 30k alumnos haria falta una instancia bastante mas grande todavia, ver rds.tf"
  type        = string
  default     = "db.t4g.small"
}
