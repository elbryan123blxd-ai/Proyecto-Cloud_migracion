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
  description = "Una por AZ. GoTrue, PostgREST, Aurora y los VPC Endpoints viven aca -- sin acceso directo desde Internet"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "aurora_min_acu" {
  description = "Minimo de Aurora Capacity Units. 0 = puede pausarse del todo cuando nadie la usa"
  type        = number
  default     = 0
}

variable "aurora_max_acu" {
  description = "Maximo de ACU para el clon (sin trafico real, no hace falta mas)"
  type        = number
  default     = 1
}
