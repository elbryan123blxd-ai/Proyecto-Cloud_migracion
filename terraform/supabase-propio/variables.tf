variable "gotrue_image_tag" {
  description = "Tag de la imagen de GoTrue en ECR (ver ecr.tf). Se sube a mano con docker push -- Terraform no construye imagenes"
  type        = string
  default     = "latest"
}

variable "postgrest_image_tag" {
  description = "Tag de la imagen de PostgREST en ECR (ver ecr.tf)"
  type        = string
  default     = "latest"
}

variable "fargate_cpu" {
  description = "CPU de cada tarea (unidad Fargate: 256 = 0.25 vCPU). Minimo posible -- es el clon, sin trafico real"
  type        = number
  default     = 256
}

variable "fargate_memoria" {
  description = "Memoria (MB) de cada tarea. 512 es el minimo que Fargate permite combinar con 256 CPU"
  type        = number
  default     = 512
}

variable "autoscaling_min_tareas" {
  description = "Piso de tareas por servicio -- nunca 0: a diferencia de Aurora, un servicio ECS no 'duerme' solo"
  type        = number
  default     = 1
}

variable "autoscaling_max_tareas" {
  description = "Techo de tareas por servicio durante un pico (ver prueba de carga, Fase 5)"
  type        = number
  default     = 3
}

variable "autoscaling_cpu_objetivo" {
  description = "Porcentaje de CPU que dispara agregar una tarea mas (target tracking)"
  type        = number
  default     = 60
}

variable "gotrue_mailer_autoconfirm" {
  description = "true = confirma emails solo (sin SMTP real). Este clon no tiene servidor de correo propio"
  type        = bool
  default     = true
}
