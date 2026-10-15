# =============================================================================
# RDS PostgreSQL normal -- reemplaza a Aurora Serverless v2.
#
# Por que: la cuenta "Ready Set Build" (free tier) NO permite crear clusters
# Aurora con "full configuration" (VPC propia, security group propio,
# contrasena) -- solo permite "Express Configuration", que crea el cluster
# FUERA de cualquier VPC, con acceso publico por Internet y solo autenticacion
# IAM. Eso rompe el pilar de seguridad central de este proyecto (la base
# aislada en subred privada). Confirmado 2026-10-15 con un CreateDBCluster
# real que fallo, y con la documentacion oficial de AWS: "You cannot associate
# express clusters with a VPC" -- no es un parametro que falte, es una
# restriccion sin excepcion dentro del free tier.
#
# RDS PostgreSQL (una instancia, no un cluster Aurora) NO tiene esta
# restriccion: permite VPC propia, security group propio y contrasena normal,
# igual que el diseno original. El unico cambio real es que esto NO "escala a
# cero" como Aurora Serverless v2 -- es una instancia chica, pero fija.
#
# IMPORTANTE -- esto alcanza para EL CLON (sin trafico real), no para
# produccion. Si esto sirviera de verdad a los 60 admins + 30k alumnos
# documentados en CLAUDE.md, hace falta una instancia bastante mas grande
# (familia r6g/m6g, varios GB de RAM) -- el tamano exacto no se puede
# calcular solo en teoria, requiere la prueba de carga real de la Fase 5.
# =============================================================================

resource "aws_db_subnet_group" "aurora" {
  name       = "academia-premier-aurora"
  subnet_ids = aws_subnet.privada[*].id

  tags = { Name = "academia-premier-db-subnets" }
}

resource "random_password" "aurora_master" {
  length  = 32
  special = false # algunos motores de RDS rechazan ciertos caracteres especiales en la password del master
}

resource "aws_db_instance" "db" {
  identifier = "academia-premier-db"
  engine     = "postgres"
  # Version disponible en el momento de aplicar -- si AWS no tiene esta
  # version exacta en us-east-2, ajustar aca (no es Aurora: las versiones
  # disponibles son las de RDS Postgres normal, pueden diferir).
  engine_version = "15.4"

  instance_class    = var.db_instance_class # db.t4g.micro por defecto -- el minimo, alcanza para el clon
  allocated_storage = 20                    # GB -- el minimo tipico, de sobra para datos de prueba
  storage_type      = "gp2"                 # gp3 no entra en el free tier, gp2 si

  db_name  = "academia_premier"
  username = "academia_premier_admin"
  password = random_password.aurora_master.result

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id] # mismo security group ya creado, protege Postgres igual

  multi_az            = false # el free tier solo permite Single-AZ para RDS normal
  publicly_accessible = false # nunca accesible directo desde Internet, igual que el diseno original

  storage_encrypted       = true
  skip_final_snapshot     = true # clon de portfolio, no produccion -- no hace falta snapshot al destruir
  backup_retention_period = 1    # minimo posible: este clon no necesita retencion larga de backups
  deletion_protection     = false

  tags = { Name = "academia-premier-db" }
}
