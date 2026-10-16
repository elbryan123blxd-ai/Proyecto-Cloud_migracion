# =============================================================================
# Un solo ALB al frente de los dos servicios -- como pide docs/PLAN.md.
#
# Sin dominio propio todavia (eso llega en Fase 3 con Amplify/CloudFront),
# asi que por ahora es HTTP sin certificado. Y sin Kong (el gateway que usa
# Supabase Cloud para reescribir "/auth/v1/*" y "/rest/v1/*" hacia cada
# servicio), un ALB comun no puede partir trafico por PATH sin reescritura
# -- por eso el reparto aca es por PUERTO: 80 = PostgREST, 8081 = GoTrue.
# Sigue siendo "un solo ALB", solo que con dos listeners.
# =============================================================================

resource "aws_lb" "principal" {
  name               = "academia-premier-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [local.sg_alb_id]
  subnets            = local.subredes_publicas

  tags = { Name = "academia-premier-alb" }
}

# --- Target group de PostgREST (la API) -------------------------------------
resource "aws_lb_target_group" "postgrest" {
  name        = "academia-premier-tg-postgrest"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip" # obligatorio con Fargate en modo awsvpc -- no hay instancia EC2 que registrar

  health_check {
    path                = "/" # PostgREST responde 200 en la raiz con el esquema OpenAPI -- sirve de healthcheck gratis
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = { Name = "academia-premier-tg-postgrest" }
}

resource "aws_lb_listener" "postgrest" {
  load_balancer_arn = aws_lb.principal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.postgrest.arn
  }
}

# --- Target group de GoTrue (auth) ------------------------------------------
resource "aws_lb_target_group" "gotrue" {
  name        = "academia-premier-tg-gotrue"
  port        = 9999
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = { Name = "academia-premier-tg-gotrue" }
}

resource "aws_lb_listener" "gotrue" {
  load_balancer_arn = aws_lb.principal.arn
  port              = 8081
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gotrue.arn
  }
}
