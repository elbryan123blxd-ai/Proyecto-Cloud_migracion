variable "expected_account_id" {
  description = "Proyecto AWS permitido para este despliegue."
  type        = string
  default     = "519119252721"
}

variable "environment" {
  description = "Entorno independiente; rama main corresponde a preprod."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "preprod", "prod"], var.environment)
    error_message = "Usar dev, preprod o prod."
  }
}

variable "tfstate_bucket" {
  description = "Bucket del bootstrap NUEVO que contiene el estado de red del entorno."
  type        = string
  validation {
    condition     = var.tfstate_bucket != "academia-premier-tfstate-994b4178" && length(var.tfstate_bucket) > 3
    error_message = "Indicar el bucket nuevo; el bucket historico no pertenece a este proyecto."
  }
}

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
