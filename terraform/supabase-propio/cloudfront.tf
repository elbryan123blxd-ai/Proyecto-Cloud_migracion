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

# --- Las 2 funciones que hacen de Kong ---------------------------------------
#
# Kong, en el Supabase real, hace 2 trabajos distintos que nosotros le
# copiamos por separado: reescribe el path (ver "quitar_prefijo" abajo) Y
# le agrega los headers de CORS a cada respuesta. Sin el segundo, el
# navegador bloquea el pedido con "No 'Access-Control-Allow-Origin' header
# is present" -- GoTrue y PostgREST, solos, no agregan ese header; en el
# Supabase real nunca hace falta que lo hagan porque Kong ya se los pone.
#
# Van en 2 eventos distintos de CloudFront porque hacen falta en 2
# momentos distintos:
# - "viewer-request" (quitar_prefijo): corre ANTES de llegar al origen.
#   Reescribe el path, y ademas responde el preflight (pedido OPTIONS que
#   manda el navegador antes de un POST/PATCH/DELETE "no simple") directo
#   en el borde, sin ni llegar a GoTrue/PostgREST -- mas rapido y evita que
#   la tarea de ECS tenga que lidiar con eso.
# - "viewer-response" (agregar_cors): corre DESPUES de que el origen ya
#   respondio. Le agrega el header a la respuesta real (login exitoso,
#   datos de PostgREST, etc.) -- esto el viewer-request no lo puede hacer,
#   todavia no existe la respuesta en ese momento.
#
# Nota de seguridad, para el video: esto refleja CUALQUIER origen que
# pida (`Access-Control-Allow-Origin: <el que vino>`) en vez de una lista
# fija -- la lista fija no alcanza porque hay 5 apps, cada una en su
# puerto en localhost (orígenes distintos) y despues en su propio dominio
# de Amplify. Es una simplificacion valida para este clon de portfolio
# (sin datos ni usuarios reales); en produccion de verdad conviene una
# lista explicita de dominios permitidos.
resource "aws_cloudfront_function" "quitar_prefijo" {
  name    = "academia-premier-quitar-prefijo"
  runtime = "cloudfront-js-2.0"
  comment = "Saca /auth/v1 y /rest/v1 del path, y responde el preflight CORS (OPTIONS) en el borde"
  publish = true

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var headers = request.headers;
      var uri = request.uri;

      if (uri.startsWith('/auth/v1')) {
        request.uri = uri.substring(8) || '/';
      } else if (uri.startsWith('/rest/v1')) {
        request.uri = uri.substring(8) || '/';
      }

      if (request.method === 'OPTIONS') {
        var origin = headers.origin ? headers.origin.value : '*';
        var pedidos = headers['access-control-request-headers']
          ? headers['access-control-request-headers'].value
          : 'apikey, authorization, content-type, x-client-info, prefer, range';

        return {
          statusCode: 204,
          statusDescription: 'No Content',
          headers: {
            'access-control-allow-origin': { value: origin },
            'access-control-allow-credentials': { value: 'true' },
            'access-control-allow-methods': { value: 'GET, POST, PUT, PATCH, DELETE, OPTIONS' },
            'access-control-allow-headers': { value: pedidos },
            'access-control-max-age': { value: '86400' }
          }
        };
      }

      return request;
    }
  EOT
}

resource "aws_cloudfront_function" "agregar_cors" {
  name    = "academia-premier-agregar-cors"
  runtime = "cloudfront-js-2.0"
  comment = "Le agrega el header de CORS a la respuesta real (login, datos de PostgREST, etc.)"
  publish = true

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var response = event.response;
      var origin = request.headers.origin ? request.headers.origin.value : '';

      if (origin) {
        response.headers['access-control-allow-origin'] = { value: origin };
        response.headers['access-control-allow-credentials'] = { value: 'true' };
      }

      return response;
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
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.agregar_cors.arn
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
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.agregar_cors.arn
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

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.quitar_prefijo.arn
    }
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.agregar_cors.arn
    }
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
