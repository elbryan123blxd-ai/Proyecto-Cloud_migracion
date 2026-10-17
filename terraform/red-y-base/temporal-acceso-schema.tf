# TEMPORAL -- borrar este archivo (y aplicar de nuevo) en cuanto se corra
# de nuevo db/fix-auth-users-tokens-null.sql (version generica) contra la base.

resource "aws_security_group_rule" "temporal_cloudshell_a_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.aurora.id
  source_security_group_id = "sg-012ff890e19c5d853" # default de la VPC, el que usa CloudShell-VPC
  description              = "TEMPORAL -- arreglar TODAS las columnas de texto NULL de auth.users. Sacar despues."
}
