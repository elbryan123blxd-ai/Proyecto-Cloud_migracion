# Migracion de un SaaS multi-tenant a AWS serverless

Replica sobre AWS de **Academia Premier**, un SaaS de gestion para academias
preuniversitarias del Peru que hoy corre en Supabase + Vercel.

El objetivo es demostrar la migracion completa: red, base de datos, autenticacion,
API, almacenamiento, despliegue y observabilidad, todo con Terraform y sin una sola
credencial permanente.

> Produccion sigue en Supabase y Vercel. Esto es una replica con datos generados.
> Ningun dato real de alumnos entra a esta infraestructura.

**Estado:** Fase 1 aplicada (VPC, RDS PostgreSQL, Secrets Manager). Ver [docs/PLAN.md](docs/PLAN.md).

## Arquitectura

Version con iconos de AWS, siempre actualizada: [abrir el diagrama](https://app.diagrams.net/?url=https://raw.githubusercontent.com/elbryan123blxd-ai/Proyecto-Cloud_migracion/main/docs/arquitectura.drawio)

```
                              Internet
                                 |
                           [ CloudFront ]
                                 |
                 +---------------+---------------+
                 |                               |
           [ Apps Next.js ]                   [ ALB ]
            Lambda / Amplify                 (unico, por
                 |                          path: /auth/*)
            [ S3 ]                               |
         (archivos)          +--- VPC privada ---+-----------------------+
                              |  sin acceso directo desde Internet       |
                              |                                         |
                        [ GoTrue (auth) ]  <------->  [ PostgREST (API) ]
                          ECS Fargate                   ECS Fargate
                              |                                         |
                              +------------------+----------------------+
                                                  |
                                        [ RDS PostgreSQL ]
                                      Postgres 15.19, db.t4g.micro
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

**Un solo Application Load Balancer, no dos.** Un ALB no esta atado a un servicio: reparte
trafico segun el *path* del pedido. Con una sola regla (`/auth/*` -> GoTrue, el resto ->
PostgREST) alcanza un ALB para los dos servicios, evitando pagar un segundo load balancer
completo solo por tener dos backends distintos.

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

Pendiente. Se documenta al cerrar la Fase 1. El bootstrap de Terraform
(`terraform/bootstrap/`) ya esta escrito -- falta correr `terraform apply`.
