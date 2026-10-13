# Proyecto-Cloud_migracion

## Que es esto

Replica sobre AWS de **Academia Premier**, un SaaS multi-tenant real (academias
preuniversitarias del Peru que pagan una cuota mensual por mes). Hoy corre sobre Supabase
(base, auth, storage) y Vercel (5 apps Next.js).

Este proyecto **no migra produccion**. Construye una copia con datos generados para
demostrar la arquitectura en el portfolio. Produccion sigue en Supabase y Vercel, intacta.

Codigo fuente del producto real: repo privado `Proyecto_Full_Stack2.0`. Ese codigo
**no vive aca** — este repo es solo la infraestructura de la replica.

## Reglas, en orden de importancia

1. El entorno de AWS de este proyecto **nunca** se conecta a la Supabase de produccion.
2. **Ningun dato real** de alumnos entra a este repo ni a esta infraestructura. Son
   datos de menores de edad. Solo datos generados.
3. Nada de credenciales permanentes en uso activo. Ver "Como se entra a AWS" abajo.
4. `terraform.tfstate` **nunca** se commitea — guarda contrasenas en texto plano. Backend
   remoto desde que exista (ver Fase 0 en `docs/PLAN.md`).
5. Antes de cada push: revisar que no se cuele ningun `.env`, dump de base, o clave. El
   `.gitignore` ya cubre los casos conocidos, pero revisar igual.

## Arquitectura (resumen, detalle en README.md)

| Pieza en Supabase/Vercel | Reemplazo en AWS | Por que |
|---|---|---|
| Postgres | Aurora Serverless v2, minimo 0 ACU | Escala a cero: el proyecto esta idle el 95% del tiempo |
| Auth (Supabase Auth) | GoTrue autohospedado en ECS Fargate | Las politicas RLS usan `auth.uid()`. Cognito las rompe todas y mueve la autorizacion del multi-tenant de la base al codigo |
| API autogenerada | PostgREST en ECS Fargate | Mismo motivo que arriba: mantiene pool de conexiones estable, por eso Fargate y no Lambda |
| Storage | S3 | — |
| Hosting (Vercel) | Amplify / Lambda + CloudFront | Serverless donde si tiene sentido |
| Variables de entorno | Secrets Manager | — |
| Todo lo anterior | Terraform | Reproducible y destruible |

No se usa EKS/Kubernetes aca: ya existe `Proyecto-DevOps` con esa arquitectura. Repetirla
no suma nada distinto al portfolio.

## La cuenta de AWS

Cuenta nueva del programa de creditos **"AWS Ready Set Build"**. Dos restricciones propias
de este tipo de cuenta, confirmadas a mano, no documentadas por AWS de antemano:

- **Una sola region habilitada: us-east-2 (Ohio).** Todo el proyecto vive ahi.
- **IAM Identity Center (SSO) no esta disponible** ("Access to this service is not
  supported"). Motivo tecnico: estas cuentas ya pertenecen a la Organization propia de
  AWS, y una cuenta no puede tener su propio Identity Center si ya es miembro de otra.

### Como se entra a AWS (por la restriccion de arriba)

No hay SSO disponible, asi que el plan original (`aws sso login`) no aplica a esta cuenta.
En su lugar:

1. Usuario IAM dedicado (no root), con **MFA obligatorio**.
2. Una access key existe, pero **no se usa directo para trabajar**. Vive guardada local,
   nunca en este repo, nunca pegada en un chat.
3. Para trabajar se saca una sesion temporal con el codigo MFA:
   ```
   aws sts get-session-token --serial-number <arn-del-mfa> --token-code <codigo>
   ```
   Esas credenciales vencen en horas. Son las que se usan para Terraform y el CLI.

Esto reemplaza al SSO como forma de no tener una credencial permanente viva. Es mas manual
que `aws sso login`, pero el resultado de seguridad es equivalente.

El permission set es `AdministratorAccess` sobre esta cuenta, porque Bryan es el unico
usuario y no se conoce de antemano el set completo de servicios a tocar (decision
consciente, no por descuido — justificable en una cuenta personal de practica, no en un
entorno de equipo).

## Presupuesto

~$180 USD de creditos AWS, vencen aprox. 180 dias desde el alta de la cuenta (ver fecha
real en la consola, Billing). Se agotan sin reembolso.

Los tres gastos que funden creditos sin avisar:

| Servicio | Costo tipico | Como se evita aca |
|---|---|---|
| NAT Gateway | ~$32/mes | No se usa. VPC Endpoints o subredes publicas con security groups cerrados |
| Load Balancer | ~$17/mes | Uno solo para todos los servicios |
| Base encendida 24/7 | ~$13-43/mes | Aurora Serverless v2 escala a 0 |

Objetivo: **$35-50/mes con todo arriba**, cerca de $0 con el entorno apagado.

Pendiente de armar: AWS Budget con alerta a $50 y a $100 (Fase 0).

## Fases

Ver `docs/PLAN.md` para el detalle completo con checkboxes. Resumen:

0. Fundaciones (budget, backend remoto, datos generados) — **en curso**
1. Red y base (VPC, Aurora, Secrets Manager)
2. El Supabase propio (ECS Fargate: GoTrue + PostgREST, S3, un ALB)
3. Las apps Next.js
4. CI/CD (GitHub Actions con OIDC, restringido a este repo y a `main`)
5. Cierre (observabilidad, README final, video, destroy)

## El schema (`db/schema.sql`)

Extraido via MCP de la Supabase real de Academia Premier -- solo estructura (columnas,
FKs, funciones, RLS), cero filas de dato real. Alcance decidido 2026-10-12:

- **Tutor, Alumno y Profesor funcionan al 100%.**
- **Dashboard (director) funciona salvo** facturacion SUNAT, gastos y cierres de caja.
- **El panel del dueno de la plataforma queda afuera a proposito** (suscripciones, modo
  soporte, roles de plataforma) -- es el backoffice de venta del SaaS, no la arquitectura
  cloud que este repo viene a demostrar.
- `answer_sheets`/`ocr_results` (el pipeline de OCR que lee las hojas de examen escaneadas)
  tampoco se portan: es vision por computadora, no infraestructura. `exam_results` guarda
  los puntajes ya calculados, como dato generado.

25 tablas, 21 funciones de permisos (`mi_academia()`, `is_director()`, `mi_alumno()`,
`mi_tutor()`, etc.), RLS completa. Tres funciones se simplificaron a proposito frente a
produccion porque dependian del backoffice de plataforma excluido: `mi_academia()` ya no
pasa por modo soporte, `academia_activa()` siempre da `true`, `es_plataforma()` siempre
da `false`.

## Estado actual / pendientes abiertos

- [x] MFA activo en el usuario IAM
- [x] Schema SQL (`db/schema.sql`)
- [ ] AWS Budget con alerta
- [ ] Borrar el bucket S3 que se creo a mano por consola durante las pruebas
- [ ] Generador de datos falsos para las 25 tablas
- [ ] Decidir y documentar el backend remoto de Terraform (S3 + DynamoDB) antes del primer
      `apply` real, para no dejar el `tfstate` en local
