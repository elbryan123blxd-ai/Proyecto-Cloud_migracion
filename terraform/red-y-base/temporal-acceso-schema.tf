# TEMPORAL -- borrar este archivo (y aplicar de nuevo) en cuanto se termine
# de cargar db/schema.sql contra la base.
#
# Separado a proposito del diseno permanente (network.tf/rds.tf): sg-aurora
# solo deberia confiar en sg-servicios (GoTrue/PostgREST). Esta regla extra
# le da acceso tambien al security group "default" de la VPC, que es el que
# usa el CloudShell-VPC desde donde cargamos el schema a mano, una sola vez,
# antes de que GoTrue/PostgREST existan (Fase 2).
#
# Agregado 2026-10-16. Sacar apenas termine la carga del schema.

resource "aws_security_group_rule" "temporal_cloudshell_a_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.aurora.id
  source_security_group_id = "sg-012ff890e19c5d853" # default de la VPC, el que usa CloudShell-VPC
  description              = "TEMPORAL -- CloudShell para cargar db/schema.sql a mano. Sacar despues."
}
