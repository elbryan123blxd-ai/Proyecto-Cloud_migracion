# TEMPORAL -- borrar este archivo (y aplicar de nuevo) en cuanto termine de
# correr scripts/seed/generar_datos.py contra la base.

resource "aws_security_group_rule" "temporal_cloudshell_a_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.aurora.id
  source_security_group_id = "sg-012ff890e19c5d853" # default de la VPC, el que usa CloudShell-VPC
  description              = "TEMPORAL -- correr scripts/seed/generar_datos.py a mano. Sacar despues."
}
