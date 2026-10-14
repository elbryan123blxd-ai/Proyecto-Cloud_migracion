# VPC con subredes publicas (el ALB) y privadas (GoTrue, PostgREST, Aurora).
# A proposito SIN NAT Gateway -- ver CLAUDE.md "Presupuesto" para el porque.
# Lo que las subredes privadas necesitan de AWS (S3, ECR, Secrets Manager,
# CloudWatch Logs) sale por VPC Endpoints, no por salida general a Internet.

resource "aws_vpc" "principal" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "academia-premier-vpc" }
}

resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "academia-premier-igw" }
}

# --- Subredes publicas: solo el ALB vive aca ---
resource "aws_subnet" "publica" {
  count                   = length(var.subredes_publicas_cidr)
  vpc_id                  = aws_vpc.principal.id
  cidr_block              = var.subredes_publicas_cidr[count.index]
  availability_zone       = data.aws_availability_zones.disponibles.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "academia-premier-publica-${count.index}" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.principal.id
  }

  tags = { Name = "academia-premier-rt-publica" }
}

resource "aws_route_table_association" "publica" {
  count          = length(aws_subnet.publica)
  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# --- Subredes privadas: GoTrue, PostgREST, Aurora, VPC Endpoints ---
resource "aws_subnet" "privada" {
  count             = length(var.subredes_privadas_cidr)
  vpc_id            = aws_vpc.principal.id
  cidr_block        = var.subredes_privadas_cidr[count.index]
  availability_zone = data.aws_availability_zones.disponibles.names[count.index]

  tags = { Name = "academia-premier-privada-${count.index}" }
}

# Sin ruta a un Internet/NAT Gateway: esta route table solo tiene las rutas
# locales de la VPC (implicitas) mas lo que el VPC Endpoint de S3 agregue solo.
resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "academia-premier-rt-privada" }
}

resource "aws_route_table_association" "privada" {
  count          = length(aws_subnet.privada)
  subnet_id      = aws_subnet.privada[count.index].id
  route_table_id = aws_route_table.privada.id
}

# =============================================================================
# SECURITY GROUPS -- quien le puede hablar a quien
# =============================================================================

resource "aws_security_group" "alb" {
  name        = "academia-premier-alb"
  description = "Unico punto que recibe trafico directo de Internet (via CloudFront)"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description = "HTTPS desde Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Al puerto de GoTrue/PostgREST en Fargate"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "academia-premier-sg-alb" }
}

resource "aws_security_group" "servicios" {
  name        = "academia-premier-servicios"
  description = "GoTrue y PostgREST en ECS Fargate -- solo reciben del ALB"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "Desde el ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "A Aurora y a los VPC Endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "academia-premier-sg-servicios" }
}

resource "aws_security_group" "aurora" {
  name        = "academia-premier-aurora"
  description = "Postgres -- solo recibe de GoTrue/PostgREST"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "Postgres desde los servicios"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.servicios.id]
  }

  tags = { Name = "academia-premier-sg-aurora" }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "academia-premier-vpc-endpoints"
  description = "Interface endpoints (ECR, Secrets Manager, CloudWatch Logs) -- solo reciben de los servicios"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "HTTPS desde los servicios"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.servicios.id]
  }

  tags = { Name = "academia-premier-sg-vpc-endpoints" }
}

# =============================================================================
# VPC ENDPOINTS -- reemplazan al NAT Gateway, solo para los servicios de AWS
# que los contenedores realmente necesitan. Nada de salida general a Internet.
# =============================================================================

# Gateway endpoint: gratis, se asocia directo a la route table (no usa ENI ni SG)
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.principal.id
  service_name    = "com.amazonaws.us-east-2.s3"
  route_table_ids = [aws_route_table.privada.id]

  tags = { Name = "academia-premier-vpce-s3" }
}

# Interface endpoints: tienen costo por hora + trafico, uno por servicio
locals {
  interface_endpoints = {
    ecr_api         = "com.amazonaws.us-east-2.ecr.api"
    ecr_dkr         = "com.amazonaws.us-east-2.ecr.dkr"
    secrets_manager = "com.amazonaws.us-east-2.secretsmanager"
    logs            = "com.amazonaws.us-east-2.logs"
  }
}

resource "aws_vpc_endpoint" "interfaces" {
  for_each            = local.interface_endpoints
  vpc_id              = aws_vpc.principal.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.privada[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "academia-premier-vpce-${each.key}" }
}
