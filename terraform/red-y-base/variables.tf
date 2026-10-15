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
  description = "Tamano de la instancia RDS. db.t4g.micro alcanza para el clon (sin trafico real) -- para produccion real con 30k alumnos haria falta una instancia bastante mas grande, ver rds.tf"
  type        = string
  default     = "db.t4g.micro"
}
