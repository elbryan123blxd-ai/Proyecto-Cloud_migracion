# =============================================================================
# Aurora Serverless v2 Postgres -- la base de datos.
#
# min_acu = 0 -> se pausa sola cuando nadie la usa (ver CLAUDE.md
# "Presupuesto" y "Capacidad objetivo"). El esquema (db/schema.sql) y los
# datos falsos (scripts/seed/) se cargan DESPUES de que esto exista -- no
# es parte de este modulo, son pasos manuales posteriores.
# =============================================================================

# --- Donde vive Aurora dentro de la VPC: las 2 subredes privadas -------------
# RDS/Aurora exige un "subnet group" con al menos 2 subredes en AZs distintas,
# aunque el cluster termine usando solo una instancia.
resource "aws_db_subnet_group" "aurora" {
  name       = "academia-premier-aurora"
  subnet_ids = aws_subnet.privada[*].id # las mismas 2 subredes privadas de network.tf

  tags = { Name = "academia-premier-aurora-subnets" }
}

# --- La contrasena del usuario master: generada, nunca escrita a mano -------
# Terraform la crea una sola vez. Vive en el tfstate (por eso el tfstate
# JAMAS se commitea, ver .gitignore) y despues se copia a Secrets Manager
# en secrets.tf -- que es por donde GoTrue/PostgREST la van a pedir de verdad.
resource "random_password" "aurora_master" {
  length  = 32
  special = false # Aurora rechaza algunos caracteres especiales en la password del master
}

# --- El cluster Aurora en si -------------------------------------------------
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "academia-premier-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # "provisioned" + el bloque serverlessv2_scaling de abajo = Serverless v2
  engine_version     = "15.4"

  database_name   = "academia_premier"
  master_username = "academia_premier_admin"
  master_password = random_password.aurora_master.result

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id] # el "sg-aurora" de network.tf: solo entra sg-servicios

  # ESTO es lo que hace que sea "serverless" y no una base fija prendida 24/7:
  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_acu # 0 por defecto -- puede pausarse del todo
    max_capacity = var.aurora_max_acu # 1 por defecto -- el clon no tiene trafico real que pida mas
  }

  storage_encrypted       = true
  skip_final_snapshot     = true # clon de portfolio, no produccion -- no hace falta snapshot al destruir
  backup_retention_period = 1    # minimo posible: este clon no necesita retencion larga de backups

  tags = { Name = "academia-premier-aurora" }
}

# --- La instancia que realmente ejecuta las consultas ------------------------
# En Aurora, el "cluster" de arriba es la capa de almacenamiento + config.
# Esta instancia es el computo real -- la que escala segun serverlessv2_scaling.
resource "aws_rds_cluster_instance" "aurora" {
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless" # obligatorio para que use el escalado serverless de arriba
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  tags = { Name = "academia-premier-aurora-instancia" }
}
