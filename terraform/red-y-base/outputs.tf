output "vpc_id" {
  value = aws_vpc.principal.id
}

output "environment" {
  value = var.environment
}

output "project_account_id" {
  value = var.expected_account_id
}

output "subredes_datos_ids" {
  description = "Privadas exclusivas de PostgreSQL."
  value       = aws_subnet.datos[*].id
}

output "rutas_privadas_ids" {
  value = { application = aws_route_table.privada.id, data = aws_route_table.datos.id }
}

output "vpc_endpoints_ids" {
  value = { interfaces = { for k, ep in aws_vpc_endpoint.interfaces : k => ep.id }, s3 = aws_vpc_endpoint.s3.id }
}

output "db_instance_id" {
  description = "Identificador RDS para las dimensiones de CloudWatch"
  value       = aws_db_instance.db.identifier
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
  description = "Host de la base (RDS PostgreSQL) para que GoTrue/PostgREST se conecten"
  value       = aws_db_instance.db.address
}

output "aurora_secret_arn" {
  description = "ARN del secreto en Secrets Manager con las credenciales de la base"
  value       = aws_secretsmanager_secret.aurora_credentials.arn
}
