# Migracion de un SaaS multi-tenant a AWS serverless

Replica sobre AWS de **Academia Premier**, un SaaS de gestion para academias
preuniversitarias del Peru que hoy corre en Supabase + Vercel.

El objetivo es demostrar la migracion completa: red, base de datos, autenticacion,
API, almacenamiento, despliegue y observabilidad, todo con Terraform y sin una sola
credencial permanente.

> Produccion sigue en Supabase y Vercel. Esto es una replica con datos generados.
> Ningun dato real de alumnos entra a esta infraestructura.

**Estado:** Fases 0, 1 y 2 completas y verificadas en vivo — red, base de datos, GoTrue y
PostgREST corriendo en ECS Fargate detras de CloudFront, con 30.000 alumnos de prueba
cargados. El login real de la aplicacion funciona contra esta infraestructura. Fase 3 (las
apps) en curso. Ver [docs/PLAN.md](docs/PLAN.md).

> 📖 **¿Primera vez acá? Empezá por [docs/COMO-FUNCIONA.md](docs/COMO-FUNCIONA.md)** — explica
> el proyecto entero desde cero: Terraform, cada servicio de AWS, networking y seguridad con
> analogias, y los problemas reales que aparecieron en el camino (con sus soluciones).

## Arquitectura

Version con iconos de AWS, siempre actualizada: [abrir el diagrama](https://app.diagrams.net/?url=https://raw.githubusercontent.com/elbryan123blxd-ai/Proyecto-Cloud_migracion/main/docs/arquitectura.drawio)

```
                              Internet
                                 |
                                 |  HTTPS
                                 v
                        [ CloudFront ]  <-- el "Kong" del clon: una sola URL,
                                 |          reparte por path y le saca el prefijo
                 +---------------+---------------+
                 |                               |
      /auth/v1/* |                               | /rest/v1/*
                 v                               v
            [ ALB :8081 ]                   [ ALB :80 ]
                 |          (un unico ALB, dos listeners)
   +-------------+------- VPC privada --------+--------------+
   |              sin acceso directo desde Internet          |
   |                                                         |
   |       [ GoTrue (auth) ]              [ PostgREST (API) ]|
   |         ECS Fargate                     ECS Fargate     |
   |              |                               |          |
   |              +---------------+---------------+          |
   |                              |                          |
   |                    [ RDS PostgreSQL ]                   |
   |                  Postgres 15.19, db.t4g.micro           |
   |                  (RLS: aisla por academia)              |
   +---------------------------------------------------------+
                                  |
                        [ Secrets Manager ]

   Aparte, no es runtime de la app -- es tooling para construir todo lo de arriba:
   [ Terraform ] --guarda el estado--> [ S3 tfstate ] --toma el lock--> [ DynamoDB ]
```

## De donde sale cada pieza

| En Supabase | En AWS |
|---|---|
| Postgres | RDS PostgreSQL (`db.t4g.micro`) -- el plan original era Aurora Serverless v2, cambiado por restriccion del free tier |
| Auth | GoTrue en ECS Fargate |
| API autogenerada | PostgREST en ECS Fargate |
| Storage | S3 |
| Hosting (Vercel) | CloudFront + Lambda / Amplify |
| Variables de entorno | Secrets Manager |

## El schema (`db/schema.sql`)

25 tablas extraidas via MCP de la Supabase real, solo estructura (columnas, FKs,
funciones, RLS), cero datos reales. Alcance decidido a proposito: **Tutor, Alumno y
Profesor funcionan al 100%**. El Dashboard funciona salvo facturacion SUNAT, gastos y
cierres de caja. El panel del dueno de la plataforma (suscripciones, modo soporte)
queda afuera -- es el backoffice de venta del SaaS, no la arquitectura cloud que este
repo viene a demostrar.

## Decisiones que vale la pena explicar

**La autenticacion no se migra a Cognito.** La seguridad multi-tenant vive en politicas
RLS de Postgres que usan `auth.uid()`. Cambiar a Cognito obliga a reescribirlas todas y
mueve la autorizacion de la base al codigo de la aplicacion: cualquier consulta que olvide
filtrar por academia deja de estar protegida. Autohospedar GoTrue mantiene esa red de
seguridad intacta.

**Los servicios de auth y API van en Fargate, no en Lambda.** GoTrue y PostgREST son
servidores HTTP que mantienen un pool de conexiones contra Postgres. Lambda levanta copias
independientes que abririan cada una las suyas hasta agotar el limite de la base. Se evaluo
Lambda + RDS Proxy como alternativa "paga solo lo que usas", pero con el trafico real
esperado (ver mas abajo) el RDS Proxy termina corriendo 24/7 igual, y evitar el "cold start
storm" del pico de asistencia necesitaria Provisioned Concurrency programada -- que vuelve a
costar lo mismo que Fargate. Sin ahorro real, mas complejidad.

**Sin NAT Gateway: VPC Endpoints en su lugar.** Un NAT Gateway abre salida a *todo*
Internet y cobra por hora exista o no trafico. Los servicios en la VPC privada (GoTrue,
PostgREST) solo necesitan hablar con S3, ECR, Secrets Manager y CloudWatch Logs -- nunca
con Internet en general. Un VPC Endpoint por cada uno de esos servicios da acceso privado
y especifico, sin tocar Internet, mas barato y mas seguro que una salida general.

**Un solo Application Load Balancer, no dos.** Un ALB no esta atado a un servicio: alcanza
uno para los dos backends, evitando pagar un segundo load balancer completo. Acá reparte
por *puerto* (80 -> PostgREST, 8081 -> GoTrue), no por path, por el motivo de abajo.

**CloudFront reemplaza a Kong.** Supabase usa Kong por dentro para que una sola URL
reparta entre varios servicios: mira el path (`/auth/v1/...`, `/rest/v1/...`), **le saca el
prefijo** y lo reenvia. Un ALB sabe repartir por path pero **no sabe reescribirlo**, y el
cliente oficial de Supabase asume esa estructura de URL. Ademas, el navegador bloquea que
una pagina HTTPS llame a una API HTTP, y un certificado propio necesita un dominio que no
tenemos. CloudFront resuelve las dos cosas: da HTTPS gratis con su propio dominio, y con dos
CloudFront Functions de ocho lineas hace el trabajo completo de Kong (reescribir el path y
agregar los headers de CORS). **Resultado: las 5 apps Next.js no cambian una sola linea de
codigo** — solo apuntan a otra URL. Detalle completo en
[docs/COMO-FUNCIONA.md](docs/COMO-FUNCIONA.md#6-cloudfront-el-reemplazo-de-kong).

## Capacidad objetivo y costos

Disenado pensando en un escenario de trafico real, no solo "que funcione":
**60 administradores/directores/tutores** conectados de 8am a 8pm, y **30,000 alumnos**
marcando asistencia por QR en 3 oleadas predecibles (20% a las 7:30am, 30% a las 7:40am,
50% de 7:45am en adelante), con el mismo pico repitiendose 4 veces al mes en la tarde.

| Escenario | Costo estimado/mes |
|---|---|
| Este clon (datos de prueba, sin trafico real) | **$48-60** |
| Si sirviera de verdad a Academia Premier, con el trafico de arriba | **~$120-170** |

En el segundo escenario, Fargate, el ALB y ahora tambien la base de datos son los que no
bajan de precio aunque no haya trafico. El plan original era Aurora Serverless v2 (escala
sola en el pico y baja despues), pero la cuenta de creditos no permite usarla con una VPC
propia -- con RDS normal se perdio esa elasticidad, asi que la base pasa a ser un gasto
fijo mas, dimensionado para el peor momento del dia. Ver el reporte completo de costos
y el detalle de la decision en [CLAUDE.md](CLAUDE.md).

## Como levantarlo

Tres modulos de Terraform, en orden. Cada uno guarda su estado por separado:

```bash
# 1. El backend remoto: bucket S3 para el estado + tabla DynamoDB para el candado.
#    Este guarda SU estado en local a proposito (no puede guardarlo en el bucket
#    que todavia no existe).
cd terraform/bootstrap && terraform init && terraform apply

# 2. Red y base: VPC, subredes, security groups, VPC Endpoints, RDS, Secrets Manager.
cd ../red-y-base && terraform init && terraform apply

# 3. El "Supabase propio": ECR, ECS Fargate, ALB, CloudFront, S3, IAM, auto-scaling.
cd ../supabase-propio && terraform init && terraform apply
```

Entre el 2 y el 3 hay pasos manuales (cargar el esquema SQL, subir las imagenes a ECR,
crear los roles de Postgres que Supabase trae de fabrica). El orden exacto, con los
comandos, esta en [CLAUDE.md](CLAUDE.md#como-se-aplico-en-la-practica-2026-10-1617).

Para destruir todo y no dejar nada cobrando, el orden es al reves (3, 2, 1) con
`terraform destroy`.
