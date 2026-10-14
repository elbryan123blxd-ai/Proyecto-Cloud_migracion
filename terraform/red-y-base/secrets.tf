# La contrasena de Aurora vive ACA, no en codigo ni en variables de entorno
# planas. GoTrue y PostgREST la piden al arrancar, via el VPC Endpoint de
# Secrets Manager -- nunca queda escrita en ningun archivo de este repo.

resource "aws_secretsmanager_secret" "aurora_credentials" {
  name        = "academia-premier/aurora/credenciales"
  description = "Usuario y contrasena del master de Aurora -- generada por Terraform, nunca a mano"

  tags = { Name = "academia-premier-secret-aurora" }
}

resource "aws_secretsmanager_secret_version" "aurora_credentials" {
  secret_id = aws_secretsmanager_secret.aurora_credentials.id
  secret_string = jsonencode({
    username = aws_rds_cluster.aurora.master_username
    password = random_password.aurora_master.result
    host     = aws_rds_cluster.aurora.endpoint
    port     = aws_rds_cluster.aurora.port
    dbname   = aws_rds_cluster.aurora.database_name
  })
}
