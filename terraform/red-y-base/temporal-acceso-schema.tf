# TEMPORAL -- borrar este archivo (y aplicar de nuevo) en cuanto se
# diagnostique por que PostgREST no puede autenticarse como "authenticator".
#
# Reabierto de nuevo 2026-10-17: PostgREST falla con "password
# authentication failed for user authenticator" -- hay que probar la
# conexion directo con psql para confirmar si es la password o algo de
# SSL/encriptacion (el error de PostgREST mezcla ambas cosas).

resource "aws_security_group_rule" "temporal_cloudshell_a_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.aurora.id
  source_security_group_id = "sg-012ff890e19c5d853" # default de la VPC, el que usa CloudShell-VPC
  description              = "TEMPORAL -- diagnosticar auth de PostgREST. Sacar despues."
}
