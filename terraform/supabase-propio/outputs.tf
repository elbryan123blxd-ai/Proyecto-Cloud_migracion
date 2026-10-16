output "alb_dns_name" {
  description = "URL publica del ALB -- puerto 80 PostgREST, puerto 8081 GoTrue (ver alb.tf)"
  value       = aws_lb.principal.dns_name
}

output "ecr_gotrue_url" {
  description = "A donde hacer docker push de la imagen de GoTrue -- ver README de este modulo"
  value       = aws_ecr_repository.gotrue.repository_url
}

output "ecr_postgrest_url" {
  description = "A donde hacer docker push de la imagen de PostgREST"
  value       = aws_ecr_repository.postgrest.repository_url
}

output "s3_archivos_bucket" {
  value = aws_s3_bucket.archivos.id
}

output "authenticator_secret_arn" {
  description = "ARN del secreto con el password del rol 'authenticator' -- necesario para db/post-gotrue-roles.sql"
  value       = aws_secretsmanager_secret.authenticator.arn
}
