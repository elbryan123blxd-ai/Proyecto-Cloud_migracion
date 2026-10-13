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
| Base | Aurora Serverless v2, minimo 0 ACU | Se apaga sola cuando nadie la usa. El proyecto va a estar idle el 95% del tiempo |
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
| Base encendida 24/7 | ~$13-43/mes | Aurora escala a 0 |

Objetivo: **$35-50/mes** con todo arriba, y casi $0 con el entorno apagado.

## Fases

### Fase 0 - Fundaciones (sin costo)
- [ ] AWS Budget con alerta a $50 y a $100
- [x] Acceso a AWS sin claves permanentes en uso (IAM user + MFA + sesion
      temporal, no SSO -- la cuenta "Ready Set Build" no lo soporta)
- [x] Confirmar en que cuenta AWS estan los creditos -- cuenta nueva
      "Ready Set Build", solo region us-east-2 (ver CLAUDE.md)
- [x] Exportar el esquema SQL de Supabase (solo estructura, sin datos) --
      `db/schema.sql`. 25 tablas, 21 funciones de permisos, RLS completa.
      Alcance decidido 2026-10-12: Tutor/Alumno/Profesor al 100%, Dashboard
      sin facturacion SUNAT/gastos/cierres de caja, panel de plataforma afuera
- [ ] Borrar el bucket S3 que se creo a mano por consola durante las pruebas
- [ ] Generador de datos falsos para las 25 tablas de db/schema.sql

### Fase 1 - Red y base
- [ ] VPC, subredes, security groups (sin NAT Gateway)
- [ ] Aurora Serverless v2 Postgres, minimo 0 ACU
- [ ] Secrets Manager para las credenciales
- [ ] Cargar esquema + datos generados

### Fase 2 - El Supabase propio
- [ ] Cluster ECS Fargate
- [ ] GoTrue (auth)
- [ ] PostgREST (API)
- [ ] S3 para archivos
- [ ] Un solo ALB al frente

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
- [ ] README con diagrama de arquitectura y costos
- [ ] Video
- [ ] `terraform destroy` y verificar que no quedo nada cobrando

## Reglas

1. El entorno de AWS **nunca** se conecta a la Supabase de produccion.
2. Ningun dato real entra a este repo ni a esta infraestructura.
3. El codigo de las 5 apps Next.js no vive aca: es el producto por el que pagan las academias.
4. Nada de credenciales permanentes. OIDC para CI, SSO para la laptop.
5. Teardown al terminar cada sesion larga de trabajo.
