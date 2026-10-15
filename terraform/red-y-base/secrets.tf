# =============================================================================
# Secrets Manager -- donde vive la contrasena de Aurora.
#
# La alternativa mala seria escribirla en el codigo de GoTrue/PostgREST o en
# una variable de entorno plana (queda expuesta para siempre si el repo es
# publico, hasta en el historial de commits). En cambio, GoTrue y PostgREST
# la van a PEDIR al arrancar, via el VPC Endpoint de Secrets Manager (ver
# network.tf) -- nunca queda escrita en ningun archivo de este repo.
#
# Nadie que use la app la ve -- ni siquiera el superadmin de la plataforma.
# Solo los propios servicios al arrancar, y vos como admin de AWS si algun
# dia necesitas revisarla a mano en la consola.
# =============================================================================

# --- El "contenedor" del secreto: solo el nombre y la descripcion -----------
resource "aws_secretsmanager_secret" "aurora_credentials" {
  name        = "academia-premier/aurora/credenciales"
  description = "Usuario y contrasena del master de Aurora -- generada por Terraform, nunca a mano"

  tags = { Name = "academia-premier-secret-aurora" }
}

# --- El contenido real del secreto, como JSON --------------------------------
# Todo esto sale de valores que YA genero Terraform en aurora.tf (el cluster
# y la password aleatoria) -- aca solo los empaquetamos juntos para que
# GoTrue/PostgREST tengan, en un solo lugar, todo lo que necesitan para
# conectarse: con quien, con que contrasena, a que host, puerto y base.
resource "aws_secretsmanager_secret_version" "aurora_credentials" {
  secret_id = aws_secretsmanager_secret.aurora_credentials.id
  secret_string = jsonencode({
    username = aws_rds_cluster.aurora.master_username # definido en aurora.tf
    password = random_password.aurora_master.result   # generada en aurora.tf, nunca a mano
    host     = aws_rds_cluster.aurora.endpoint        # el host al que GoTrue/PostgREST se conectan
    port     = aws_rds_cluster.aurora.port
    dbname   = aws_rds_cluster.aurora.database_name
  })
}
