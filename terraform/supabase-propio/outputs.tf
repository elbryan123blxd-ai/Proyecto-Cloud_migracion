output "alb_dns_name" {
  description = "URL publica del ALB -- puerto 80 PostgREST, puerto 8081 GoTrue (ver alb.tf). Para probar a mano; las apps usan CloudFront"
  value       = aws_lb.principal.dns_name
}

output "api_url" {
  description = "LA URL de la API: esto es lo que va en NEXT_PUBLIC_SUPABASE_URL de las apps. HTTPS, con /auth/v1 y /rest/v1 ruteados como en el Supabase real"
  value       = "https://${aws_cloudfront_distribution.api.domain_name}"
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
