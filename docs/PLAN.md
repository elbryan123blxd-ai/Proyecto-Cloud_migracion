# Plan de migracion

## Que es esto

Academia Premier es un SaaS multi-tenant real: academias preuniversitarias peruanas que
pagan una cuota mensual. Hoy corre sobre Supabase (base, auth, storage) y Vercel (5 apps
Next.js).

Este proyecto **no migra produccion**. Construye una replica de esa plataforma sobre AWS,
con datos generados, para demostrar la arquitectura. Produccion sigue en Supabase y Vercel
y no se toca.

## Decisiones ya tomadas

| Decision | Eleccion | Por que |
|---|---|---|
| Alcance | Clon de portfolio | Hay academias pagando; migrar en vivo es riesgo sin beneficio |
| Auth | Supabase Auth autohospedado (GoTrue) | Las politicas RLS usan `auth.uid()`. Migrar a Cognito obliga a reescribirlas todas y saca la seguridad de la base |
| Compute de servicios | ECS Fargate | GoTrue y PostgREST mantienen pool de conexiones. En Lambda cada copia abre el suyo y agota la base |
| Compute de apps | Amplify / Lambda + CloudFront | Serverless real donde si conviene |
| Base | RDS PostgreSQL normal (`db.t4g.micro`) | El plan original era Aurora Serverless v2, pero el free tier de esta cuenta no permite Aurora con VPC propia (solo "Express Configuration", publica y sin password). Cambiado 2026-10-15, ver CLAUDE.md |
| Datos | Generados | Son datos de menores de edad. No van a una infra de practica |
| IaC | Terraform | Todo reproducible y destruible |

### Por que no serverless puro

Serverless puro (Lambda + DynamoDB) obligaria a tirar Postgres y reescribir el producto.
La arquitectura es serverless donde suma y administrada donde hace falta.

### Por que no Kubernetes

Ya existe un proyecto propio con EKS, ArgoCD y Argo Rollouts. Repetirlo no agrega nada.

## Presupuesto

Creditos AWS: **$160**, vencen el **2027-04-13**.

Los tres que funden la cuenta sin avisar:

| Servicio | Costo | Como lo evitamos |
|---|---|---|
| NAT Gateway | ~$32/mes | No se usa. VPC Endpoints o subredes publicas con security groups cerrados |
| Load Balancer | ~$17/mes | Uno solo para todos los servicios |
| Base encendida 24/7 | ~$13-43/mes | RDS no escala a 0 (no es Aurora) -- se usa la instancia mas chica posible para compensar |

Objetivo: **$48-60/mes** con todo arriba (subio desde $35-50 porque RDS no se puede
pausar como Aurora Serverless v2), y casi $0 con el entorno apagado salvo por la base.

## Fases

### Fase 0 - Fundaciones (sin costo)
- [x] AWS Budget con alerta a $50 y a $100
- [x] Acceso a AWS sin claves permanentes en uso (IAM user + MFA + sesion
      temporal, no SSO -- la cuenta "Ready Set Build" no lo soporta) --
      el MFA nunca se habia configurado de verdad pese a estar marcado como
      hecho; corregido y armado de cero 2026-10-16 (ver CLAUDE.md)
- [x] Confirmar en que cuenta AWS estan los creditos -- cuenta nueva
      "Ready Set Build", solo region us-east-2 (ver CLAUDE.md)
- [x] Exportar el esquema SQL de Supabase (solo estructura, sin datos) --
      `db/schema.sql`. 25 tablas, 21 funciones de permisos, RLS completa.
      Alcance decidido 2026-10-12: Tutor/Alumno/Profesor al 100%, Dashboard
      sin facturacion SUNAT/gastos/cierres de caja, panel de plataforma afuera
- [x] `terraform apply` del bootstrap (`terraform/bootstrap/`) -- bucket
      `academia-premier-tfstate-994b4178` y tabla `academia-premier-tflock`
      creados en us-east-2, 2026-10-14
- [x] Borrar el bucket S3 que se creo a mano por consola durante las pruebas
      -- confirmado 2026-10-14: no existe ningun otro bucket aparte del
      del bootstrap. La nota quedo desactualizada, no habia nada que borrar
- [x] Generador de datos falsos para las 25 tablas de db/schema.sql --
      `scripts/seed/generar_datos.py`. **Corrido de verdad 2026-10-17**:
      5 academias, 30.000 alumnos, 100 personal (directores/admin_sede/
      docentes/tutores), 30.100 usuarios en `auth.users` via GoTrue.
      Password de prueba para todos: `Demo1234!`

### Fase 1 - Red y base
- [x] Aplicada 2026-10-15 (`terraform/red-y-base/`): VPC, subredes publicas/privadas,
      security groups, VPC Endpoints (S3, ECR, Secrets Manager, CloudWatch Logs),
      RDS PostgreSQL (`academia-premier-db`, Postgres 15.19, `db.t4g.micro` --
      cambiado desde Aurora Serverless v2 por restriccion del free tier, ver
      CLAUDE.md), Secrets Manager. Confirmado en consola, us-east-2
- [x] Cargar `db/schema.sql` contra la base -- hecho 2026-10-16 via CloudShell
      (VPC environment) con IP privada directa. 25 tablas, 88 policies RLS,
      57 funciones (21 propias + extensiones) confirmadas en la base real.
      Hallazgo en el camino: las funciones de permisos usan `auth.uid()`, que
      no existia hasta crear un stub real en `schema.sql` -- ver CLAUDE.md
- [ ] Correr `scripts/seed/generar_datos.py` (requiere GoTrue, Fase 2)
- [ ] Sacar el acceso temporal de CloudShell a la base
      (`terraform/red-y-base/temporal-acceso-schema.tf`) -- preparado, falta
      que Bryan corra `terraform apply`

### Fase 2 - El Supabase propio -- COMPLETA 2026-10-17
- [x] Modulo `terraform/supabase-propio/` -- cluster ECS Fargate, task
      definitions de GoTrue y PostgREST, ALB con 2 listeners (80 PostgREST,
      8081 GoTrue -- sin path rewrite, ver CLAUDE.md), ECR, Secrets Manager
      (JWT + rol authenticator), S3, auto-scaling por CPU. Aplicado, ambos
      servicios en subred privada (el plan original, sin NAT)
- [x] Imagenes oficiales de GoTrue (`v2.187.0`, no hay `:latest` en Docker
      Hub) y PostgREST (`:latest`) subidas a ECR
- [x] `db/post-gotrue-roles.sql`, `db/gotrue-postgres-role.sql` (rol
      `postgres` que pide una migracion propia de GoTrue) y
      `db/post-gotrue-fks.sql` corridos contra la base real
- [x] GoTrue y PostgREST verificados en vivo atras del ALB: `/health` en
      GoTrue (puerto 8081) y el esquema OpenAPI completo en PostgREST
      (puerto 80) responden 200 OK

**Hallazgo central de esta fase** (detalle completo en CLAUDE.md): el
primer intento de GoTrue para bajar su imagen de ECR fallaba por timeout.
Se sospecho mal -- DNS privada de los VPC Endpoints -- y se probo hasta
mover los servicios a subred publica (revertido). La causa real: ECR
guarda las capas de las imagenes en S3, y el Gateway Endpoint de S3 usa
IPs publicas como destino (solo cambia el ruteo, nunca el DNS) -- el
security group de los servicios no dejaba salir hacia esas IPs. Fix de una
linea (agregar la prefix list de S3 al egress), sin moverse de subred
privada.

### Fase 3 - Las apps
- [ ] Desplegar las apps Next.js
- [ ] Apuntarlas a la nueva URL
- [ ] Verificar que las politicas RLS siguen aislando por academia

### Fase 4 - CI/CD
- [ ] GitHub Actions con OIDC, restringido a este repo y a la rama main
- [ ] `terraform plan` en cada PR
- [ ] tflint y escaneo de seguridad

### Fase 5 - Cierre
- [ ] CloudWatch: dashboard y alarmas
- [ ] **Prueba de carga real — "el clip epico" del video.** Simular el escenario
      documentado en CLAUDE.md (60 admins + 30k alumnos en 3 oleadas: 20% a las
      7:30, 30% a las 7:40, 50% de 7:45 en adelante). Grabar el dashboard de
      CloudWatch mostrando el auto-scaling de Fargate reaccionando en vivo, no
      solo contarlo. Generar la carga desde dentro de AWS (EC2/Fargate en la
      misma region), no desde la laptop — si no, el cuello de botella es la
      laptop, no la arquitectura. Herramienta candidata: k6 (tiene dashboard
      propio, queda bien en video) o Artillery.
      **Requiere Fases 1-4 ya desplegadas** — no se puede probar contra algo
      que no existe. Cuidado con el costo: el auto-scaling real gasta creditos
      de verdad durante la prueba.
- [ ] README con diagrama de arquitectura y costos
- [ ] Video
- [ ] `terraform destroy` y verificar que no quedo nada cobrando

## Reglas

1. El entorno de AWS **nunca** se conecta a la Supabase de produccion.
2. Ningun dato real entra a este repo ni a esta infraestructura.
3. El codigo de las 5 apps Next.js no vive aca: es el producto por el que pagan las academias.
4. Nada de credenciales permanentes. OIDC para CI, SSO para la laptop.
5. Teardown al terminar cada sesion larga de trabajo.
