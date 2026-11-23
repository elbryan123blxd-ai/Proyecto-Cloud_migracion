# Pruebas sin credenciales ni llamadas reales. Verifican limites entre capas.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-2a", "us-east-2b"] }
  }
}
mock_provider "random" {}

run "aislamiento_dev" {
  command = apply

  assert {
    condition = (
      length(aws_subnet.publica) + length(aws_subnet.privada) + length(aws_subnet.datos) == 6 &&
      toset(aws_db_subnet_group.aurora.subnet_ids) == toset(aws_subnet.datos[*].id) &&
      alltrue([for ep in aws_vpc_endpoint.interfaces : toset(ep.subnet_ids) == toset(aws_subnet.privada[*].id)])
    )
    error_message = "RDS debe quedar exclusivamente en datos y los endpoints exclusivamente en aplicacion, con seis subredes."
  }

  assert {
    condition = (
      toset(aws_vpc_endpoint.s3.route_table_ids) == toset([aws_route_table.privada.id]) &&
      length(aws_route_table.datos.route) == 0 &&
      length(setintersection(toset(aws_subnet.datos[*].id), toset(aws_subnet.privada[*].id))) == 0 &&
      alltrue([for subnet in aws_subnet.datos : !subnet.map_public_ip_on_launch]) &&
      !aws_db_instance.db.publicly_accessible && !aws_db_instance.db.multi_az
    )
    error_message = "Datos no debe tener IP publica, S3 Gateway ni ruta de salida; dev debe ser Single-AZ."
  }

  assert {
    condition = alltrue([
      for rule in aws_security_group.servicios.egress :
      rule.from_port != 5432 || toset(rule.cidr_blocks) == toset(var.subredes_datos_cidr)
    ])
    error_message = "La salida SQL de ECS debe dirigirse a datos, no a aplicacion."
  }
}

run "preprod_multi_az" {
  command = plan
  variables {
    environment = "preprod"
    db_multi_az = true
  }
  assert {
    condition     = aws_db_instance.db.multi_az && aws_db_instance.db.identifier == "academia-premier-preprod-db"
    error_message = "Multi-AZ debe ser configurable y su nombre debe aislar el entorno."
  }
}
