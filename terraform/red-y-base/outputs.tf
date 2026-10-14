output "vpc_id" {
  value = aws_vpc.principal.id
}

output "subredes_publicas_ids" {
  description = "Donde va el ALB en la Fase 2"
  value       = aws_subnet.publica[*].id
}

output "subredes_privadas_ids" {
  description = "Donde van GoTrue y PostgREST en la Fase 2"
  value       = aws_subnet.privada[*].id
}

output "sg_servicios_id" {
  description = "Security group que la Fase 2 debe asignarle a las tareas de Fargate"
  value       = aws_security_group.servicios.id
}

output "sg_alb_id" {
  value = aws_security_group.alb.id
}

output "aurora_endpoint" {
  description = "Host de Aurora para que GoTrue/PostgREST se conecten"
  value       = aws_rds_cluster.aurora.endpoint
}

output "aurora_secret_arn" {
  description = "ARN del secreto en Secrets Manager con las credenciales de Aurora"
  value       = aws_secretsmanager_secret.aurora_credentials.arn
}
