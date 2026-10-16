# =============================================================================
# Secretos propios de Fase 2 -- el password del master de Aurora (Fase 1) NO
# se reutiliza aca a proposito: GoTrue y PostgREST no deberian conectarse
# como super-usuario de la base, cada uno usa su propio rol de Postgres con
# permisos acotados. Ver db/post-gotrue-roles.sql para la creacion real de
# esos roles (paso manual, mismo patron que db/post-gotrue-fks.sql).
# =============================================================================

# --- El JWT secret: lo que firma y valida los tokens de sesion ---------------
# GoTrue lo usa para FIRMAR el JWT que le da a cada usuario que hace login.
# PostgREST usa el MISMO secreto para VALIDAR que ese JWT es legitimo antes
# de confiar en el rol/uid que dice llevar adentro. Si no coinciden, todo
# login de GoTrue le resulta invalido a PostgREST.
resource "random_password" "jwt_secret" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name        = "academia-premier/servicios/jwt-secret"
  description = "Firma los JWT que GoTrue emite y que PostgREST valida -- generado por Terraform, nunca a mano"

  tags = { Name = "academia-premier-secret-jwt" }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}

# --- El rol "authenticator" que usa PostgREST --------------------------------
# PostgREST se conecta a Postgres con ESTE rol (no con el master de Aurora),
# y despues hace "SET ROLE anon/authenticated/service_role" segun lo que diga
# el JWT de cada pedido. Asi, un bug en PostgREST nunca puede hacer mas de lo
# que ese rol de bajo privilegio tiene permitido -- el master jamas se expone
# a trafico de internet, ni indirecto.
resource "random_password" "authenticator" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "authenticator" {
  name        = "academia-premier/postgrest/authenticator"
  description = "Rol de Postgres que usa PostgREST -- se crea a mano con db/post-gotrue-roles.sql"

  tags = { Name = "academia-premier-secret-authenticator" }
}

resource "aws_secretsmanager_secret_version" "authenticator" {
  secret_id = aws_secretsmanager_secret.authenticator.id
  secret_string = jsonencode({
    username = "authenticator"
    password = random_password.authenticator.result
  })
}

# --- Las URLs de conexion completas, ya armadas ------------------------------
# GoTrue y PostgREST esperan un connection string completo, no host/puerto/
# usuario/password sueltos. Se arman aca (con datos de Aurora que vienen del
# remote state de Fase 1, ver main.tf) y se guardan como secretos propios --
# asi la tarea de ECS solo pide UN secreto, no 5 variables sueltas.
resource "aws_secretsmanager_secret" "gotrue_database_url" {
  name        = "academia-premier/gotrue/database-url"
  description = "Connection string completa que usa GoTrue -- usa el master de Aurora, busca en el schema auth"

  tags = { Name = "academia-premier-secret-gotrue-db-url" }
}

resource "aws_secretsmanager_secret_version" "gotrue_database_url" {
  secret_id     = aws_secretsmanager_secret.gotrue_database_url.id
  secret_string = "postgres://${local.aurora.username}:${urlencode(local.aurora.password)}@${local.aurora.host}:${local.aurora.port}/${local.aurora.dbname}?search_path=auth"
}

resource "aws_secretsmanager_secret" "postgrest_database_url" {
  name        = "academia-premier/postgrest/database-url"
  description = "Connection string completa que usa PostgREST -- usa el rol authenticator, NUNCA el master"

  tags = { Name = "academia-premier-secret-postgrest-db-url" }
}

resource "aws_secretsmanager_secret_version" "postgrest_database_url" {
  secret_id     = aws_secretsmanager_secret.postgrest_database_url.id
  secret_string = "postgres://authenticator:${urlencode(random_password.authenticator.result)}@${local.aurora.host}:${local.aurora.port}/${local.aurora.dbname}"
}
