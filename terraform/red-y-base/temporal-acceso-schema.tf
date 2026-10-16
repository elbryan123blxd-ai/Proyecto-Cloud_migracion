# TEMPORAL -- borrar este archivo (y aplicar de nuevo) en cuanto se terminen
# de correr db/post-gotrue-roles.sql y db/post-gotrue-fks.sql contra la base.
#
# Reabierto para Fase 2 (2026-10-16): igual que la vez que cargamos
# db/schema.sql, hace falta conectarse a mano una vez mas para crear los
# roles de Postgres que usa PostgREST (anon/authenticated/service_role/
# authenticator) y, si GoTrue ya corrio sus migraciones, las FKs a
# auth.users. Separado a proposito del diseno permanente (network.tf/rds.tf):
# sg-aurora solo deberia confiar en sg-servicios (GoTrue/PostgREST). Esta
# regla extra le da acceso tambien al security group "default" de la VPC,
# que es el que usa CloudShell-VPC.

resource "aws_security_group_rule" "temporal_cloudshell_a_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.aurora.id
  source_security_group_id = "sg-012ff890e19c5d853" # default de la VPC, el que usa CloudShell-VPC
  description              = "TEMPORAL -- correr db/post-gotrue-roles.sql y post-gotrue-fks.sql a mano. Sacar despues."
}
