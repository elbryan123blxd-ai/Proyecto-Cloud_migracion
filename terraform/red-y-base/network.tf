# =============================================================================
# VPC con subredes publicas (el ALB) y privadas (GoTrue, PostgREST, Aurora).
#
# A proposito SIN NAT Gateway -- ver CLAUDE.md "Presupuesto" para el porque.
# Lo que las subredes privadas necesitan de AWS (S3, ECR, Secrets Manager,
# CloudWatch Logs) sale por VPC Endpoints (al final de este archivo), no por
# salida general a Internet.
# =============================================================================

# --- La VPC: el "terreno" entero donde vive todo lo demas ---------------------
resource "aws_vpc" "principal" {
  cidr_block           = var.vpc_cidr # 10.0.0.0/16 por defecto -- todo el rango de IPs disponible
  enable_dns_support   = true         # necesario para que los VPC Endpoints (mas abajo) resuelvan por DNS
  enable_dns_hostnames = true

  tags = { Name = "academia-premier-vpc" }
}

# --- Internet Gateway: la unica puerta de la VPC hacia/desde Internet ---------
# Solo lo usan las subredes PUBLICAS (via su route table, abajo). Las privadas
# no tienen ningun camino hacia este recurso -- por eso no necesitan NAT.
resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "academia-premier-igw" }
}

# =============================================================================
# SUBREDES PUBLICAS -- aca va a vivir el ALB en la Fase 2. Es la UNICA parte
# de toda la arquitectura que recibe trafico directo de Internet.
# =============================================================================

resource "aws_subnet" "publica" {
  count = length(var.subredes_publicas_cidr) # 2, una por zona de disponibilidad (AZ)

  vpc_id                  = aws_vpc.principal.id
  cidr_block              = var.subredes_publicas_cidr[count.index] # 10.0.0.0/24, 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.disponibles.names[count.index]
  map_public_ip_on_launch = true # lo que se cree aca recibe IP publica automatica

  tags = { Name = "academia-premier-publica-${count.index}" }
}

# Tabla de rutas de las subredes publicas: "todo lo que no sea de la VPC,
# mandalo al Internet Gateway". Esto es lo que las hace "publicas" de verdad.
resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0" # cualquier destino que no sea la propia VPC
    gateway_id = aws_internet_gateway.principal.id
  }

  tags = { Name = "academia-premier-rt-publica" }
}

# Asocia cada subred publica con la tabla de rutas de arriba.
resource "aws_route_table_association" "publica" {
  count          = length(aws_subnet.publica)
  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# =============================================================================
# SUBREDES PRIVADAS -- GoTrue, PostgREST, Aurora y los VPC Endpoints viven
# aca. Nada de lo que hay en esta subred es alcanzable directo desde Internet.
# =============================================================================

resource "aws_subnet" "privada" {
  count = length(var.subredes_privadas_cidr) # 2, una por AZ (Aurora lo exige)

  vpc_id            = aws_vpc.principal.id
  cidr_block        = var.subredes_privadas_cidr[count.index] # 10.0.10.0/24, 10.0.11.0/24
  availability_zone = data.aws_availability_zones.disponibles.names[count.index]
  # Sin "map_public_ip_on_launch": lo que se cree aca NUNCA recibe IP publica.

  tags = { Name = "academia-premier-privada-${count.index}" }
}

# Tabla de rutas de las subredes privadas: a proposito EMPIEZA VACIA, sin
# ninguna ruta hacia un Internet Gateway ni un NAT Gateway. Solo tiene las
# rutas locales de la VPC (implicitas, Terraform no las declara) mas la que
# el VPC Endpoint de S3 va a agregar el solo, mas abajo en este archivo.
# Esta es la razon tecnica real de "sin NAT Gateway": no es que lo bloqueemos
# con un firewall, directamente no existe ningun camino hacia afuera.
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
# SECURITY GROUPS -- el firewall de cada pieza. Se encadenan: nadie se salta
# un escalon.
#
#   Internet -> [sg-alb] -> [sg-servicios] -> [sg-aurora]
#                                           -> [sg-vpc-endpoints]
# =============================================================================

# --- sg-alb: la "puerta de calle". Lo unico que acepta trafico de Internet ---
resource "aws_security_group" "alb" {
  name        = "academia-premier-alb"
  description = "Unico punto que recibe trafico directo de Internet (via CloudFront)"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description = "HTTPS desde Internet (cualquiera)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Hacia GoTrue/PostgREST (el ALB reparte por path, ver README)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # todo protocolo, todo puerto -- restringido igual porque el destino solo puede ser la VPC
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "academia-premier-sg-alb" }
}

# --- sg-servicios: el "portero". Solo deja pasar lo que ya paso por el ALB ---
# Lo van a usar las tareas de ECS Fargate (GoTrue y PostgREST) en la Fase 2.
resource "aws_security_group" "servicios" {
  name        = "academia-premier-servicios"
  description = "GoTrue y PostgREST en ECS Fargate -- solo reciben del ALB, nunca directo de Internet"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "Desde el ALB (no desde Internet -- el ALB es el unico que puede hablarles)"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # referencia a OTRO security group, no a una IP
  }

  egress {
    description = "Hacia Aurora (puerto 5432) y hacia los VPC Endpoints (puerto 443)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "academia-premier-sg-servicios" }
}

# --- sg-aurora: la "caja fuerte". Solo GoTrue/PostgREST le pueden hablar ----
resource "aws_security_group" "aurora" {
  name        = "academia-premier-aurora"
  description = "Postgres -- ni el ALB le habla directo, solo los servicios"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "Postgres (5432) solo desde GoTrue/PostgREST"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.servicios.id]
  }

  tags = { Name = "academia-premier-sg-aurora" }
}

# --- sg-vpc-endpoints: la "ventanilla" de atencion a los servicios de AWS --
# Los interface endpoints de mas abajo usan este security group.
resource "aws_security_group" "vpc_endpoints" {
  name        = "academia-premier-vpc-endpoints"
  description = "ECR, Secrets Manager, CloudWatch Logs -- solo reciben de los servicios, nunca de afuera"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "HTTPS (443) solo desde GoTrue/PostgREST"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.servicios.id]
  }

  tags = { Name = "academia-premier-sg-vpc-endpoints" }
}

# =============================================================================
# VPC ENDPOINTS -- ACA ESTAN. Reemplazan al NAT Gateway: le dan a la subred
# privada acceso a servicios puntuales de AWS, sin salir nunca a Internet.
# Son la pieza que explica "por que no hace falta NAT Gateway" (ver CLAUDE.md).
# =============================================================================

# --- Gateway Endpoint: S3 -----------------------------------------------------
# Tipo especial, GRATIS. No usa una interfaz de red (ENI) ni security group --
# se conecta directo agregando una ruta a la tabla de rutas privada de arriba
# (por eso "rt-privada" dejaba de estar vacia: esta linea la completa).
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.principal.id
  service_name    = "com.amazonaws.us-east-2.s3"
  route_table_ids = [aws_route_table.privada.id] # agrega la ruta a S3 en la tabla privada

  tags = { Name = "academia-premier-vpce-s3" }
}

# --- Interface Endpoints: ECR, Secrets Manager, CloudWatch Logs --------------
# Tipo "Interface": SI tienen costo (~$7/mes cada uno + trafico), porque cada
# uno crea una interfaz de red real (ENI) dentro de la subred privada. A
# diferencia de S3, estos usan security group (sg-vpc-endpoints de arriba).
locals {
  interface_endpoints = {
    ecr_api         = "com.amazonaws.us-east-2.ecr.api"        # para que Fargate pida la imagen del contenedor
    ecr_dkr         = "com.amazonaws.us-east-2.ecr.dkr"        # idem, la parte que baja las capas de la imagen
    secrets_manager = "com.amazonaws.us-east-2.secretsmanager" # para que GoTrue/PostgREST pidan la password de Aurora
    logs            = "com.amazonaws.us-east-2.logs"           # para que los contenedores manden logs a CloudWatch
  }
}

resource "aws_vpc_endpoint" "interfaces" {
  for_each = local.interface_endpoints # crea UNO de estos por cada fila del mapa de arriba

  vpc_id              = aws_vpc.principal.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.privada[*].id # uno en cada subred privada (alta disponibilidad)
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true # asi "secretsmanager.us-east-2.amazonaws.com" resuelve a la IP privada, no a Internet

  tags = { Name = "academia-premier-vpce-${each.key}" }
}
