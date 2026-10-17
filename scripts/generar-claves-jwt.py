"""
Genera las claves `anon` y `service_role` del clon.

En el Supabase real estas dos claves vienen hechas con el proyecto. No son
valores random: son JWT firmados con el MISMO secreto que usan GoTrue para
firmar las sesiones y PostgREST para validarlas (el secreto que genera
Terraform en terraform/supabase-propio/secrets.tf). Por eso hay que
generarlas aca, contra nuestro propio secreto.

- `anon`: la clave publica que va en el frontend
  (NEXT_PUBLIC_SUPABASE_ANON_KEY). Dice "role: anon" -- PostgREST la lee y
  atiende el pedido como el rol `anon` de Postgres, que solo puede lo que
  las policies RLS dejen a un usuario sin loguear.
- `service_role`: la clave que SE SALTA las policies RLS (el rol tiene
  BYPASSRLS, ver db/post-gotrue-roles.sql). NUNCA va en el frontend ni en
  este repo: solo en un backend, si alguna vez hace falta.

Uso (sin instalar nada, Python 3 a secas):

    # el secreto, fresco de Secrets Manager (no lo tipees a mano)
    export JWT_SECRET=$(aws secretsmanager get-secret-value \
      --secret-id academia-premier/servicios/jwt-secret \
      --query SecretString --output text)

    python3 generar-claves-jwt.py

Imprime las dos claves. La `anon` se pega en las variables de entorno de
las apps; la `service_role` se guarda donde corresponda, nunca en git.
"""

import base64
import hashlib
import hmac
import json
import os
import sys
import time

# Mismo horizonte que usa Supabase para estas claves: 10 anios. No son
# credenciales de usuario, son identificadores de "con que rol entra este
# pedido" -- se rotan cambiando el JWT secret, no esperando que venzan.
DIEZ_ANIOS_EN_SEGUNDOS = 10 * 365 * 24 * 60 * 60


def b64url(data: bytes) -> str:
    """Base64 de URL, sin el relleno `=` -- como exige el formato JWT."""
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def firmar_jwt(payload: dict, secreto: str) -> str:
    cabecera = {"alg": "HS256", "typ": "JWT"}

    # separators sin espacios: un JWT no lleva espacios en el JSON
    partes = [
        b64url(json.dumps(cabecera, separators=(",", ":")).encode()),
        b64url(json.dumps(payload, separators=(",", ":")).encode()),
    ]
    sin_firmar = ".".join(partes).encode()

    firma = hmac.new(secreto.encode(), sin_firmar, hashlib.sha256).digest()
    return ".".join(partes) + "." + b64url(firma)


def main() -> None:
    secreto = os.environ.get("JWT_SECRET")
    if not secreto:
        sys.exit(
            "Falta JWT_SECRET. Sacalo de Secrets Manager:\n"
            "  export JWT_SECRET=$(aws secretsmanager get-secret-value "
            "--secret-id academia-premier/servicios/jwt-secret "
            "--query SecretString --output text)"
        )

    ahora = int(time.time())

    # Con un argumento (anon | service_role): imprime SOLO ese token, sin
    # nada mas alrededor -- pensado para capturarlo directo en una variable
    # (`$env:X = python generar-claves-jwt.py anon`) sin que nadie tenga que
    # copiar/pegar un string larguisimo a mano. Un solo caracter corrompido
    # en el medio (algo que ya paso varias veces esta sesion, la terminal
    # parte strings largos en varias lineas visuales) invalida la firma del
    # JWT entero, y el error que tira PostgREST no deja ver que paso.
    if len(sys.argv) > 1:
        rol_pedido = sys.argv[1]
        if rol_pedido not in ("anon", "service_role"):
            sys.exit("El argumento tiene que ser 'anon' o 'service_role'")
        token = firmar_jwt(
            {"role": rol_pedido, "iss": "supabase", "iat": ahora, "exp": ahora + DIEZ_ANIOS_EN_SEGUNDOS},
            secreto,
        )
        print(token, end="")
        return

    for rol in ("anon", "service_role"):
        token = firmar_jwt(
            {
                "role": rol,
                "iss": "supabase",
                "iat": ahora,
                "exp": ahora + DIEZ_ANIOS_EN_SEGUNDOS,
            },
            secreto,
        )
        print(f"\n{rol}:\n{token}")

    print(
        "\n--\n"
        "La clave `anon` va en NEXT_PUBLIC_SUPABASE_ANON_KEY de las apps.\n"
        "La `service_role` se salta TODAS las policies RLS: nunca al frontend, nunca a git."
    )


if __name__ == "__main__":
    main()
