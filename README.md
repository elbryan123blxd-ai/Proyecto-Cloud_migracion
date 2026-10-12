# Migracion de un SaaS multi-tenant a AWS serverless

Replica sobre AWS de **Academia Premier**, un SaaS de gestion para academias
preuniversitarias del Peru que hoy corre en Supabase + Vercel.

El objetivo es demostrar la migracion completa: red, base de datos, autenticacion,
API, almacenamiento, despliegue y observabilidad, todo con Terraform y sin una sola
credencial permanente.

> Produccion sigue en Supabase y Vercel. Esto es una replica con datos generados.
> Ningun dato real de alumnos entra a esta infraestructura.

**Estado:** Fase 0 en curso. Ver [docs/PLAN.md](docs/PLAN.md).

## Arquitectura

```
                         Internet
                            |
                      [ CloudFront ]
                            |
            +---------------+---------------+
            |                               |
      [ Apps Next.js ]                   [ ALB ]
       Lambda / Amplify                     |
                                 +----------+----------+
                                 |                     |
                          [ GoTrue (auth) ]    [ PostgREST (API) ]
                              ECS Fargate         ECS Fargate
                                 |                     |
                                 +----------+----------+
                                            |
                                  [ Aurora Serverless v2 ]
                                   Postgres, escala a 0
                                            |
                                  [ Secrets Manager ]

                          [ S3 ] archivos de usuario
```

## De donde sale cada pieza

| En Supabase | En AWS |
|---|---|
| Postgres | Aurora Serverless v2 |
| Auth | GoTrue en ECS Fargate |
| API autogenerada | PostgREST en ECS Fargate |
| Storage | S3 |
| Hosting (Vercel) | CloudFront + Lambda / Amplify |
| Variables de entorno | Secrets Manager |

## Dos decisiones que vale la pena explicar

**La autenticacion no se migra a Cognito.** La seguridad multi-tenant vive en politicas
RLS de Postgres que usan `auth.uid()`. Cambiar a Cognito obliga a reescribirlas todas y
mueve la autorizacion de la base al codigo de la aplicacion: cualquier consulta que olvide
filtrar por academia deja de estar protegida. Autohospedar GoTrue mantiene esa red de
seguridad intacta.

**Los servicios de auth y API van en Fargate, no en Lambda.** GoTrue y PostgREST son
servidores HTTP que mantienen un pool de conexiones contra Postgres. Lambda levanta copias
independientes que abririan cada una las suyas hasta agotar el limite de la base.

## Costos

Disenado para quedar en **$35-50/mes** con todo arriba y cerca de $0 con el entorno
apagado. Sin NAT Gateway, un solo Load Balancer, y la base escalando a cero.

## Como levantarlo

Pendiente. Se documenta al cerrar la Fase 1.
