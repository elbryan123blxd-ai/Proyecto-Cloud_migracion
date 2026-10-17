# =============================================================================
# CloudFront -- el "Kong" de este clon.
#
# Dos problemas que resuelve de una sola vez:
#
# 1. HTTPS. Amplify (Fase 3) sirve las apps por HTTPS obligatorio, y un
#    navegador BLOQUEA que una pagina HTTPS llame a una API por HTTP
#    (mixed content). Nuestro ALB es HTTP puro porque no hay dominio
#    propio para sacar un certificado ACM. CloudFront da HTTPS gratis con
#    su propio dominio (`algo.cloudfront.net`), sin dominio ni certificado.
#
# 2. Ruteo por path, con reescritura. El cliente oficial de Supabase
#    (`@supabase/ssr`) asume UNA sola URL y arma `<url>/auth/v1/...` para
#    auth y `<url>/rest/v1/...` para la API. En el Supabase real eso lo
#    reparte Kong, que ADEMAS le saca el prefijo antes de reenviar (GoTrue
#    espera `/token`, no `/auth/v1/token`). Un ALB comun rutea por path
#    pero NO reescribe -- por eso en Fase 2 habiamos separado por puerto.
#    CloudFront si reescribe, con una CloudFront Function de 8 lineas.
#
# Resultado: el codigo de las apps no se toca. Apuntan
# NEXT_PUBLIC_SUPABASE_URL a la URL de CloudFront y funciona igual que
# contra el Supabase real.
#
# Costo: entra en el free tier perpetuo (1 TB de salida, 10M requests y
# 2M invocaciones de CloudFront Functions por mes).
# =============================================================================

# --- La funcion que hace de Kong: le saca el prefijo al path -----------------
# Corre en el edge, antes de llegar al origen. `/auth/v1/token` -> `/token`.
resource "aws_cloudfront_function" "quitar_prefijo" {
  name    = "academia-premier-quitar-prefijo"
  runtime = "cloudfront-js-2.0"
  comment = "Saca /auth/v1 y /rest/v1 del path, como hace Kong en el Supabase real"
  publish = true

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri.startsWith('/auth/v1')) {
        request.uri = uri.substring(8) || '/';
      } else if (uri.startsWith('/rest/v1')) {
        request.uri = uri.substring(8) || '/';
      }

      return request;
    }
  EOT
}

# --- Politicas administradas de AWS -----------------------------------------
# Se buscan por nombre en vez de hardcodear el ID: son globales de AWS y los
# IDs no significan nada al leerlos.
data "aws_cloudfront_cache_policy" "sin_cache" {
  name = "Managed-CachingDisabled" # una API no se cachea: cada pedido depende del JWT de quien lo hace
}

data "aws_cloudfront_origin_request_policy" "todo_menos_host" {
  name = "Managed-AllViewerExceptHostHeader" # reenvia Authorization, apikey, cookies y query string al origen
}

resource "aws_cloudfront_distribution" "api" {
  enabled         = true
  comment         = "API del clon de Academia Premier -- GoTrue + PostgREST detras de un solo dominio HTTPS"
  price_class     = "PriceClass_100" # solo edges de US/Canada/Europa: lo mas barato. Desde Peru sale por Miami, ~70ms, de sobra para el clon
  http_version    = "http2and3"
  is_ipv6_enabled = true

  # --- Origen 1: GoTrue (puerto 8081 del ALB) -------------------------------
  origin {
    origin_id   = "gotrue"
    domain_name = aws_lb.principal.dns_name

    custom_origin_config {
      http_port              = 8081
      https_port             = 443
      origin_protocol_policy = "http-only" # el ALB no tiene certificado; el tramo CloudFront->ALB va por HTTP dentro de AWS
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- Origen 2: PostgREST (puerto 80 del ALB) ------------------------------
  origin {
    origin_id   = "postgrest"
    domain_name = aws_lb.principal.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- /auth/v1/* -> GoTrue --------------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/auth/v1/*"
    target_origin_id       = "gotrue"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.sin_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.todo_menos_host.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.quitar_prefijo.arn
    }
  }

  # --- /rest/v1/* -> PostgREST ----------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/rest/v1/*"
    target_origin_id       = "postgrest"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.sin_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.todo_menos_host.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.quitar_prefijo.arn
    }
  }

  # --- Todo lo demas -> PostgREST (sin reescribir nada) ---------------------
  # Sirve para probar a mano (`curl https://<dominio>/` devuelve el esquema
  # OpenAPI). Las apps nunca pegan aca: siempre usan los prefijos de arriba.
  default_cache_behavior {
    target_origin_id       = "postgrest"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.sin_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.todo_menos_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # el certificado gratis de *.cloudfront.net
  }

  tags = { Name = "academia-premier-cloudfront-api" }
}
