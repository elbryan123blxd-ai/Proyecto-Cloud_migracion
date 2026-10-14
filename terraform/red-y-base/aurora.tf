# Aurora Serverless v2 Postgres. min_acu = 0 -> se pausa sola cuando nadie
# la usa (ver CLAUDE.md "Presupuesto" y "Capacidad objetivo"). El esquema
# (db/schema.sql) y los datos falsos (scripts/seed/) se cargan DESPUES de
# que esto exista -- no es parte de este modulo.

resource "aws_db_subnet_group" "aurora" {
  name       = "academia-premier-aurora"
  subnet_ids = aws_subnet.privada[*].id

  tags = { Name = "academia-premier-aurora-subnets" }
}

resource "random_password" "aurora_master" {
  length  = 32
  special = false # Aurora rechaza algunos caracteres especiales en la password del master
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "academia-premier-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # "provisioned" + serverlessv2_scaling_configuration = Serverless v2
  engine_version     = "15.4"

  database_name   = "academia_premier"
  master_username = "academia_premier_admin"
  master_password = random_password.aurora_master.result

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_acu
    max_capacity = var.aurora_max_acu
  }

  storage_encrypted       = true
  skip_final_snapshot     = true # clon de portfolio, no produccion -- no hace falta snapshot al destruir
  backup_retention_period = 1

  tags = { Name = "academia-premier-aurora" }
}

resource "aws_rds_cluster_instance" "aurora" {
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  tags = { Name = "academia-premier-aurora-instancia" }
}
