# TEMPORAL -- borrar este archivo (y aplicar de nuevo) en cuanto se corran
# db/gotrue-postgres-role.sql y db/post-gotrue-fks.sql contra la base.
#
# Reabierto de nuevo 2026-10-17: hace falta crear el rol "postgres" que
# GoTrue necesita para sus migraciones (ver db/gotrue-postgres-role.sql),
# y despues (si GoTrue ya corrio OK) las FKs a auth.users. Cada apply que
# toca aws_security_group.aurora hace caer esta regla como efecto
# colateral (SG con reglas inline + regla separada, ver nota en
# network.tf) -- por eso se reabre y se cierra tantas veces en este repo,
# es el comportamiento esperado, no un bug nuevo.

resource "aws_security_group_rule" "temporal_cloudshell_a_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.aurora.id
  source_security_group_id = "sg-012ff890e19c5d853" # default de la VPC, el que usa CloudShell-VPC
  description              = "TEMPORAL -- correr db/gotrue-postgres-role.sql y post-gotrue-fks.sql a mano. Sacar despues."
}
