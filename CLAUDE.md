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
| Postgres | **RDS PostgreSQL normal** (`db.t4g.micro`) -- ver nota abajo | La cuenta free tier no permite Aurora con VPC propia |
| Auth (Supabase Auth) | GoTrue autohospedado en ECS Fargate | Las politicas RLS usan `auth.uid()`. Cognito las rompe todas y mueve la autorizacion del multi-tenant de la base al codigo |
| API autogenerada | PostgREST en ECS Fargate | Mismo motivo que arriba: mantiene pool de conexiones estable, por eso Fargate y no Lambda |
| Storage | S3 | — |
| Hosting (Vercel) | Amplify / Lambda + CloudFront | Serverless donde si tiene sentido |
| Variables de entorno | Secrets Manager | — |
| Todo lo anterior | Terraform | Reproducible y destruible |

No se usa EKS/Kubernetes aca: ya existe `Proyecto-DevOps` con esa arquitectura. Repetirla
no suma nada distinto al portfolio.

## La cuenta de AWS

Cuenta nueva del programa de creditos **"AWS Ready Set Build"**. Tres restricciones propias
de este tipo de cuenta, confirmadas a mano, no documentadas por AWS de antemano:

- **Una sola region habilitada: us-east-2 (Ohio).** Todo el proyecto vive ahi.
- **IAM Identity Center (SSO) no esta disponible** ("Access to this service is not
  supported"). Motivo tecnico: estas cuentas ya pertenecen a la Organization propia de
  AWS, y una cuenta no puede tener su propio Identity Center si ya es miembro de otra.
- **Aurora no se puede usar con VPC propia en este plan -- sin excepcion.** Descubierto
  2026-10-15 al correr el primer `terraform apply` de Fase 1: `CreateDBCluster` fallo con
  `FreeTierRestrictionError`, pidiendo `WithExpressConfiguration`. Investigado a fondo: el
  AWS CLI si soporta ese flag (Terraform todavia no), pero "Express Configuration" crea el
  cluster **fuera de cualquier VPC**, con acceso publico por Internet y **solo
  autenticacion IAM** (nada de password/Secrets Manager) -- documentado oficialmente por
  AWS: *"You cannot associate express clusters with a VPC"*, *"You cannot disable the
  internet access gateway"*. Confirmado tambien que es una restriccion del **free tier en
  general** (no solo de "Ready Set Build"): "Only clusters created with express
  configuration are supported (full configuration is not available)". Rompe el pilar de
  seguridad central del proyecto (base aislada, sin acceso a Internet). VPC, subredes,
  security groups y VPC Endpoints SI se crearon bien en ese primer apply (el fallo fue
  especificamente al crear el cluster). **Decision:** cambiar de Aurora Serverless v2 a
  RDS PostgreSQL normal (`db.t4g.micro`) -- ver "El modulo de Fase 1" abajo.

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
| Base encendida 24/7 | ~$13-43/mes | Antes: Aurora Serverless v2 escala a 0. Ahora: RDS normal no puede escalar a 0 -- se usa la instancia mas chica posible (`db.t4g.micro`, ~$12-16/mes fijo) para mantener el impacto bajo |

Objetivo: **$48-60/mes con todo arriba** (subio desde los $35-50 originales -- la base ya
no se puede pausar), cerca de $0 con el entorno apagado salvo por la base (fija, no se
puede pausar). Ese numero es el costo del CLON de portfolio (datos de prueba, casi sin
trafico real). Ver abajo el costo estimado si esto sirviera de verdad a Academia Premier.

Pendiente de armar: AWS Budget con alerta a $50 y a $100 (Fase 0).

## Capacidad objetivo (si esto fuera produccion real, no el clon)

Decidido 2026-10-13, para que las decisiones de auto-scaling tengan un numero de
referencia en vez de ser arbitrarias:

- **60 administradores/directores/tutores**, conectados de forma mas o menos pareja
  de 8am a 8pm, todos los dias.
- **30,000 alumnos**, con dos patrones de pico **predecibles**, no aleatorios ni
  simultaneos:
  - Pico diario (marcar asistencia por QR), escalonado en 3 oleadas: **20% a las
    7:30am, 30% a las 7:40am, 50% de 7:45am en adelante**. El escalonamiento ayuda:
    le da tiempo al auto-scaling de Fargate a reaccionar antes de la oleada mas
    grande, en vez de recibir los 30k de golpe en el mismo segundo.
  - Pico extra: mismo volumen, 4 veces al mes, a la tarde.
- Fuera de esas ventanas, trafico bajo y disperso.

**Por que importa:** este patron (actividad casi constante 12 horas + picos masivos
pero anticipables) es la razon por la que GoTrue/PostgREST van en Fargate con
auto-scaling y no en Lambda — con Lambda, el pico de las 7:45am dispara un "cold
start storm" (cientos de instancias arrancando en frio a la vez, justo cuando 20k
personas estan parados esperando que el QR responda). Evitarlo con Provisioned
Concurrency programada termina costando lo mismo que Fargate, asi que no hay
ahorro real — Fargate 24/7 + auto-scaling en las ventanas de pico es la opcion mas
simple y pareja en costo.

**Pendiente real, no solo de papel:** el numero exacto de tareas de Fargate que hacen
falta para aguantar 20k requests en ~15 minutos no se puede calcular solo en teoria —
hace falta una prueba de carga real contra el sistema antes de llamarlo "listo para
producción". No es parte del alcance de este clon (que no tiene trafico real), pero
queda anotado como el paso que faltaria si esto alguna vez dejara de ser portfolio.

## Descuentos por compromiso (Savings Plans) -- documentado 2026-10-14

**Fargate** califica para Compute Savings Plans (1-3 anios, ~20-50% de descuento segun
termino y pago adelantado). **RDS PostgreSQL normal tambien califica** para Reserved
Instances (a diferencia de Aurora Serverless v2, que no calificaba) -- es un efecto
colateral positivo del cambio de motor: al no poder usar Aurora en este plan, terminamos
con una base que SI se puede comprometer a precio fijo en produccion real. ALB, Lambda,
CloudFront y S3 no tienen este mecanismo o no conviene aplicarlo con trafico esporadico.

Para el CLON (este repo): **ningun compromiso conviene** -- el proyecto se destruye
con `terraform destroy`, comprometerse a 1-3 anios de gasto fijo pierde plata en vez
de ahorrarla. Para el escenario de produccion real (ver capacidad objetivo arriba),
un compromiso de 1 anio bajaria el total estimado de ~$120-170 a ~$100-145/mes;
3 anios todo adelantado, a ~$85-125/mes -- ahora la porcion de Fargate **y** RDS
cambian juntas (antes solo Fargate calificaba, Aurora Serverless v2 no).

Reporte visual completo (para el video): [Costos Academia Premier](https://claude.ai/artifact/TpXWXUL6SATLWzdzPtUU7N)

## Fases

Ver `docs/PLAN.md` para el detalle completo con checkboxes. Resumen:

0. Fundaciones (budget, backend remoto, datos generados) — **en curso**
1. Red y base (VPC, RDS PostgreSQL, Secrets Manager)
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

## El diagrama (`docs/arquitectura.drawio`)

Version visual de la tabla de arquitectura de arriba, con el estilo de iconos oficial
de AWS. Para verlo siempre actualizado sin pelearse con el autosave de draw.io
pisando el pull local, abrir directo desde GitHub:

```
https://app.diagrams.net/?url=https://raw.githubusercontent.com/elbryan123blxd-ai/Proyecto-Cloud_migracion/main/docs/arquitectura.drawio
```

Estructura: capas ENTRADA -> FRONTEND -> SERVICIOS -> DATOS, con un sub-contenedor
punteado para la VPC privada (GoTrue + PostgREST + base de datos), y el backend de
Terraform (S3 + DynamoDB) en una caja aparte, marcado explicitamente como "no participa
del runtime" -- es tooling para construir la infraestructura, no parte de la app.

**Pendiente de actualizar (2026-10-15):** el icono y el texto siguen diciendo "Aurora
Serverless v2" -- ahora es RDS PostgreSQL normal (ver "El modulo de Fase 1" abajo). El
reporte de costos del video ([link](https://claude.ai/artifact/TpXWXUL6SATLWzdzPtUU7N))
tambien menciona a Aurora y necesita el mismo ajuste.

## El bootstrap de Terraform (`terraform/bootstrap/`)

**Aplicado 2026-10-14.** Backend `local` a proposito en este modulo unicamente -- no
se puede guardar el estado del bucket que guarda el estado, adentro de ese mismo
bucket, antes de que exista (ese estado vive en el disco de Bryan, nunca en git).
Creo: bucket S3 `academia-premier-tfstate-994b4178` (versionado, cifrado AES256,
acceso publico bloqueado, vacio hasta que un modulo de Fase 1+ lo use como backend
remoto) y tabla DynamoDB `academia-premier-tflock` (On-demand, vacia salvo durante
un `apply` -- el lock se borra solo al terminar). Ambos confirmados en la consola,
us-east-2. El resto de los modulos (Fase 1 en adelante) van a usar backend `s3`
apuntando a esto.

## Estado actual / pendientes abiertos

- [x] MFA activo en el usuario IAM
- [x] Schema SQL (`db/schema.sql`)
- [x] Diagrama de arquitectura (`docs/arquitectura.drawio`)
- [x] Bootstrap de Terraform aplicado (bucket + tabla DynamoDB creados)
- [x] AWS Budget con alerta a $50 y $100
- [x] Borrar el bucket S3 de prueba -- confirmado 2026-10-14: no existia,
      la nota habia quedado desactualizada
- [x] Generador de datos falsos (`scripts/seed/generar_datos.py`) -- falta
      correrlo de verdad, necesita Aurora + GoTrue desplegados (Fases 1-2)
- [x] Fase 1 aplicada 2026-10-15: VPC, subredes, security groups, VPC Endpoints,
      RDS PostgreSQL (`academia-premier-db`, Postgres 15.19, `db.t4g.micro`) y
      Secrets Manager, todo creado y confirmado en consola, us-east-2
- [ ] Cargar `db/schema.sql` contra la base -- **siguiente paso real** (ver nota
      abajo: la base no tiene IP publica, hace falta un camino para conectarse)
- [ ] Correr `scripts/seed/generar_datos.py` (despues del schema)
- [ ] Prueba de carga real (60 admins + 30k alumnos en 3 oleadas) -- ver Fase 5 en
      `docs/PLAN.md`, requiere Fases 1-4 completas primero

## El modulo de Fase 1 (`terraform/red-y-base/`)

Backend `s3` apuntando al bootstrap. Crea:

- **VPC** (`10.0.0.0/16`) con 2 subredes publicas (el ALB, Fase 2) y 2 privadas
  (GoTrue, PostgREST, la base, VPC Endpoints), una por AZ.
- **Sin NAT Gateway** -- la subred privada solo sale por VPC Endpoints: `s3`
  (Gateway, gratis), `ecr.api`/`ecr.dkr`/`secretsmanager`/`logs` (Interface,
  ~$7/mes cada uno). Ver CLAUDE.md "Presupuesto" para el razonamiento completo.
- **Security groups** en cadena: Internet -> `sg-alb` -> `sg-servicios` ->
  `sg-aurora`/`sg-vpc-endpoints`. Nada se salta un escalon. `sg-aurora` y
  `sg-vpc-endpoints` tienen egress bloqueado a proposito (nunca inician conexiones).
- **RDS PostgreSQL normal** (`rds.tf`), no Aurora -- ver abajo el por que. Postgres
  15.4, instancia `db.t4g.micro` (configurable via `var.db_instance_class`),
  Single-AZ, `storage_type = gp2` (gp3 no entra en el free tier).
- **Secrets Manager**: usuario/password/host/puerto de la base, generados por
  Terraform (`random_password`), nunca escritos a mano.

### Por que RDS normal y no Aurora Serverless v2

El plan original era Aurora Serverless v2 (escala a 0). El primer `terraform apply`
(2026-10-15) fallo: la cuenta free tier solo permite crear Aurora con "Express
Configuration", que **no admite VPC propia, ni security group propio, ni password**
(solo IAM auth, acceso publico por Internet) -- rompe el pilar de seguridad central
del proyecto. Confirmado con la documentacion oficial de AWS y con un intento real via
AWS CLI (`--with-express-configuration`), no solo con Terraform. Investigado a fondo
que no hay forma de pedir una excepcion dentro del free tier.

RDS PostgreSQL normal (una instancia, no un cluster Aurora) **no tiene esa
restriccion** -- permite VPC propia, security group propio y password igual que el
diseno original. Lo unico que se pierde es "escala a 0": una instancia RDS normal
esta siempre prendida, asi que se compensa usando la instancia mas chica posible
(`db.t4g.micro`) para mantener el costo igual de bajo que tenia el objetivo original.
Efecto colateral positivo: RDS normal SI califica para Reserved Instances a futuro
(Aurora Serverless v2 no calificaba).

**Importante para producción real (no el clon):** `db.t4g.micro` (1GB RAM) de ninguna
manera aguantaria el escenario de 60 admins + 30k alumnos documentado mas abajo -- hace
falta una instancia bastante mas grande (familia `r6g`/`m6g`). El tamano exacto es
justamente lo que la prueba de carga de la Fase 5 deberia determinar, no algo que se
pueda calcular solo en teoria.

Pendiente, en ese orden: `terraform apply` (Bryan, MFA) -> cargar
`db/schema.sql` contra la base -> correr `scripts/seed/generar_datos.py`.
