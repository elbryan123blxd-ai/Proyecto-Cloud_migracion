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

## Dos maquinas, no una

Bryan trabaja desde **dos maquinas fisicas distintas**, no es un detalle menor:

- **La laptop**: donde corre Claude Code (esta sesion). Edita archivos, los commitea y
  los pushea a GitHub -- pero eso solo los deja en el repo remoto, no en la PC de Bryan.
- **Su PC**: donde tiene todo lo demas -- CloudShell, terraform apply, Docker, el
  navegador para probar las apps. Ahi es donde Bryan realmente ejecuta las cosas.

**Por eso, cada vez que el agente edita y pushea un archivo que Bryan va a necesitar usar
(subir a CloudShell, correr un script, aplicar un `.tf`), avisarle explicitamente que
corra `git pull origin main` en su PC primero.** Pasó varias veces (2026-10-17) que Bryan
subió a CloudShell una version vieja de un archivo porque todavia no habia hecho `pull` --
perdio tiempo con errores que en realidad eran "estoy usando el archivo de ayer".

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

### Migracion a una cuenta con tarjeta (decidido 2026-10-17, en curso)

**Por que:** la cuenta "Ready Set Build" fue imponiendo restricciones que bloquearon
decisiones de arquitectura legitimas, no solo precio -- ya van 3 confirmadas (Aurora sin
VPC propia, sin SSO, y el 2026-10-17 tambien se bloqueo subir el tamano de instancia de
RDS con `FreeTierRestrictionError`). Esa ultima aparecio probando el dashboard real: la
base (`db.t4g.micro`, burstable) se quedo sin creditos de CPU bajo la carga concurrente
normal de la app (confirmado con metricas reales de CloudWatch -- ver "Fase 3" mas abajo),
y el plan free no deja subir de tamano para resolverlo. Se agregaron indices (gratis, ayudo
en parte) pero la limitacion de fondo seguia ahi, sin forma de resolverla dentro de este
plan.

**Decision:** crear una cuenta de AWS nueva, con tarjeta real cargada (aprovechando los
creditos de bienvenida para cuentas nuevas), y migrar todo ahi. Cuenta y tarjeta las carga
Bryan directo en aws.amazon.com -- el agente nunca las toca ni las ve.

**Que NO hay que rehacer:** todo el Terraform, el schema SQL, los scripts de datos y los
hallazgos ya quedan incorporados al codigo (el stub de `auth.uid()`, el egress a la prefix
list de S3, el rol `postgres` para GoTrue, los indices de rendimiento, las CloudFront
Functions de CORS, etc.) -- aplicar estos mismos modulos contra la cuenta nueva deberia ir
mucho mas rapido que la primera vez, porque ya no hay que *descubrir* estos problemas, solo
desplegar codigo que ya los tiene resueltos.

**Que SI cambia con la cuenta nueva:**
- Vuelve a estar disponible **Aurora Serverless v2 con VPC propia** (el plan original,
  descartado en Fase 1 por la restriccion del free tier) -- a evaluar si se retoma en vez
  de RDS normal.
- Se puede elegir el tamano de instancia que haga falta, sin bloqueos.
- El presupuesto deja de ser "creditos gratis que si se acaban, se acaban sin costo" y pasa
  a ser **dinero real con tarjeta real** -- la disciplina de costo (sin NAT Gateway, un solo
  ALB, `terraform destroy` al terminar sesiones largas) importa mas, no menos, a partir de
  ahora.
- Puede que la restriccion de SSO desaparezca tambien (esa restriccion especifica era por
  pertenecer a una Organization de AWS ajena, propia del programa de creditos -- una cuenta
  nueva armada directo por Bryan no deberia tenerla, a confirmar).

**3 capas nuevas de seguridad, decididas 2026-10-17, a aplicar junto con el despliegue en
la cuenta nueva** (ninguna existia en el diseno original, se suman ahora que no hay tanta
restriccion de plataforma de por medio):

- **NACLs propias** por subred (publica y privada), ademas de los security groups que ya
  existen. Ojo con el detalle tecnico: un NACL es *stateless* (a diferencia de un security
  group) -- hay que declarar la regla de ida Y la de vuelta por separado, y la de vuelta usa
  puertos efimeros (1024-65535), no el puerto real del servicio. Es la trampa clasica de
  armar un NACL y romper la conectividad sin entender por que.
- **Rotacion automatica de secretos**: Lambda + Secrets Manager, rotando la password del
  master de la base y la del rol `authenticator` cada ~30 dias. El JWT secret queda **fuera
  de alcance** a proposito -- rotarlo invalida todas las sesiones activas al instante y hay
  que coordinar que GoTrue y PostgREST lo tomen al mismo tiempo, mas complejo que el caso
  estandar que cubre la plantilla de AWS.
- **AWS WAF**, colgado de la distribucion de CloudFront (que ya existe, se engancha
  directo). Filtra patrones de ataque conocidos (SQL injection, XSS) y puede limitar
  requests por IP, antes de que el trafico le llegue a GoTrue/PostgREST.

**Descartado a proposito:** AWS Shield Advanced ($3.000/mes minimo, compromiso de 1 anio --
totalmente fuera de escala para este proyecto). Shield Standard ya viene activo gratis, sin
configurar nada, en CloudFront y el ALB, para cualquier cuenta -- no hace falta tocarlo.

**Estado (2026-10-17, tarde):** cuenta nueva en proceso de creacion. Hasta que este lista y
el usuario IAM + MFA esten armados ahi, todo lo de este documento referido a "la cuenta" o
`780017222841` sigue describiendo la cuenta vieja ("Ready Set Build") -- actualizar esta
seccion con el numero de cuenta nuevo y marcar como completa la migracion cuando corresponda.

## Presupuesto

> Esta seccion describe la cuenta "Ready Set Build" (vieja). Con la migracion de arriba,
> el presupuesto pasa a ser tarjeta real + los creditos de bienvenida de la cuenta nueva --
> actualizar estos numeros cuando la migracion este confirmada. La disciplina de costo
> (evitar NAT Gateway, un solo ALB, instancia de base chica, destruir al terminar) sigue
> aplicando igual, ahora con mas razon.

~$180 USD de creditos AWS, vencen aprox. 180 dias desde el alta de la cuenta (ver fecha
real en la consola, Billing). Se agotan sin reembolso.

Los tres gastos que funden creditos sin avisar:

| Servicio | Costo tipico | Como se evita aca |
|---|---|---|
| NAT Gateway | ~$32/mes | No se usa. VPC Endpoints o subredes publicas con security groups cerrados |
| Load Balancer | ~$17/mes | Uno solo para todos los servicios |
| Base encendida 24/7 | ~$13-43/mes | Antes: Aurora Serverless v2 escala a 0. Ahora: RDS normal no puede escalar a 0 -- sigue en `db.t4g.micro` (~$12-16/mes). Se intento subir a `db.t4g.small` el 2026-10-17 (la micro se quedo sin creditos de CPU en vivo), pero la cuenta lo rechazo (`FreeTierRestrictionError`, tercera restriccion confirmada de este plan -- las otras dos: Aurora sin VPC propia, sin SSO). El fix real: indices (gratis), ver "Fase 3 -- en curso" |

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

- [x] MFA activo en el usuario IAM -- estaba marcado como hecho pero nunca
      se habia configurado de verdad (`list-mfa-devices` devolvia `[]`).
      Armado de cero 2026-10-16 via CLI (`create-virtual-mfa-device` +
      `enable-mfa-device`, la consola no mostraba la opcion). Verificado con
      un `get-session-token` real. El usuario (`Bryan-Migracion`) sigue
      teniendo 2 Access Keys permanentes -- pendiente evaluar borrar la que
      no se usa
- [x] Schema SQL (`db/schema.sql`)
- [x] Diagrama de arquitectura (`docs/arquitectura.drawio`)
- [x] Bootstrap de Terraform aplicado (bucket + tabla DynamoDB creados)
- [x] AWS Budget con alerta a $50 y $100
- [x] Borrar el bucket S3 de prueba -- confirmado 2026-10-14: no existia,
      la nota habia quedado desactualizada
- [x] Generador de datos falsos (`scripts/seed/generar_datos.py`) --
      **corrido de verdad 2026-10-17**, ver mas abajo
- [x] Fase 1 aplicada 2026-10-15: VPC, subredes, security groups, VPC Endpoints,
      RDS PostgreSQL (`academia-premier-db`, Postgres 15.19, `db.t4g.micro`) y
      Secrets Manager, todo creado y confirmado en consola, us-east-2
- [x] `db/schema.sql` cargado contra la base real -- 2026-10-16, via CloudShell
      (VPC environment), IP privada directa (`10.0.10.206`). Confirmado: 25
      tablas, 88 policies RLS, 57 funciones (21 propias + extensiones). Ver
      "El hallazgo de auth.uid()" abajo
- [x] Acceso temporal de CloudShell a la base, cerrado -- `terraform apply`
      corrido 2026-10-16, `temporal-acceso-schema.tf` borrado del repo
- [x] Fase 2 completa 2026-10-17: GoTrue y PostgREST corriendo en ECS
      Fargate, subred privada, verificados en vivo atras del ALB (ver "El
      modulo de Fase 2" mas abajo)
- [x] Correr `scripts/seed/generar_datos.py` -- 5 academias, 30.000
      alumnos, 100 personal, 30.100 usuarios en `auth.users`. Password de
      prueba para todos: `Demo1234!`
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

### Trampa: reglas inline + `aws_security_group_rule` en el mismo grupo

Los security groups de `network.tf` declaran sus reglas **inline** (bloques
`ingress {}` / `egress {}` adentro del recurso). Un `aws_security_group` con
bloques inline se considera dueño de **todas** las reglas del grupo: en cada
apply revoca lo que no este declarado ahi adentro. Por eso, cada vez que se
agrego el acceso temporal de CloudShell como un recurso **aparte**
(`aws_security_group_rule`), pasaron estas tres cosas:

1. **Ruido en todos los planes.** `sg-aurora` y `sg-vpc-endpoints` aparecen
   como "update in-place" en CADA apply, aunque no se hayan tocado (es el
   egress vacio que se vuelve a "fijar").
2. **La regla temporal se caia sola.** Cualquier apply que tocara
   `sg-aurora` por otro motivo la revocaba sin pedirlo -- paso 3 o 4 veces,
   siempre hubo que volver a agregarla.
3. **Un apply fallado de verdad** (2026-10-17): Terraform borro la regla
   con el recurso standalone y acto seguido el `aws_security_group` intento
   borrar la misma regla otra vez -> `InvalidPermission.NotFound: The
   specified rule does not exist in this security group`. El estado real en
   AWS quedo bien (la regla si se borro); el segundo apply converge solo.

**Como hacerlo la proxima vez:** no mezclar los dos estilos. Si hace falta
una regla temporal en `sg-aurora`, agregarla como un bloque `ingress {}`
**inline mas**, comentado/descomentado en `network.tf`, en vez de crear un
`aws_security_group_rule` suelto. Mismo esfuerzo, sin ninguno de los tres
problemas de arriba. (La otra salida -- pasar todo a
`aws_vpc_security_group_ingress_rule`, el estilo moderno del provider -- no
sirve tal cual aca: el egress deny-all de `sg-aurora`/`sg-vpc-endpoints`
depende justamente del bloque `egress {}` vacio inline, que no tiene
equivalente standalone.)

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

Fase 1 cerrada del todo: ~~`terraform apply` (Bryan, MFA)~~ -> ~~cargar
`db/schema.sql` contra la base~~ -> ~~sacar el acceso temporal de
CloudShell~~ -> ~~Fase 2 (ECS Fargate + GoTrue + PostgREST + ALB)~~ ->
~~correr `scripts/seed/generar_datos.py`~~. Sigue Fase 3 (apps Next.js).

### El hallazgo de auth.uid() (2026-10-16)

Al cargar `db/schema.sql` por primera vez contra la base real, las 25 tablas y
las FKs sin `auth` entraron bien, pero **casi todas** las 21 funciones de
permisos (`mi_academia()`, `is_director()`, etc.) y, en cadena, casi todas las
`CREATE POLICY` fallaban con `schema "auth" does not exist` o
`function X() does not exist`.

Causa real: esas funciones son `language sql` (no `plpgsql`), y Postgres
**valida que los objetos referenciados existan al momento de CREATE FUNCTION**,
no recien al invocarla -- un detalle que se habia asumido al reves en una
sesion anterior. Como usan `auth.uid()` en el cuerpo, y el schema `auth` no
existe hasta que GoTrue corra sus migraciones (Fase 2), el `CREATE FUNCTION`
fallaba de entrada. Las funciones que no dependen de `auth.uid()` directa o
indirectamente (`academia_activa()`, `es_plataforma()`) si se creaban bien,
lo que en su momento oculto el alcance real del problema.

Fix aplicado: `schema.sql` ahora crea el schema `auth` y define `auth.uid()`
el mismo (la implementacion real que usa Supabase/PostgREST -- lee el claim
`sub` del JWT via `current_setting('request.jwt.claims', ...)`), antes de la
seccion de tablas. No es un parche temporal: sigue siendo correcta una vez
desplegado GoTrue/PostgREST en Fase 2. Verificado en la base real: 25 tablas,
88 policies, 57 funciones.

## El modulo de Fase 2 (`terraform/supabase-propio/`)

Escrito y validado con `terraform validate` el 2026-10-16 (sin `apply` --
ver "Como aplicarlo" abajo). Backend `s3`, misma key del bootstrap, otra
`key` (`supabase-propio/terraform.tfstate`). Lee la VPC/subredes/security
groups/secreto de Aurora de Fase 1 via `terraform_remote_state`, nunca
copiados a mano. Crea:

- **ECR** (`ecr.tf`): un repo privado cada uno para GoTrue y PostgREST. Las
  tareas de Fargate los bajan por el VPC Endpoint de ECR, en subred
  privada, sin salir nunca a Internet -- ver "El hallazgo del egress de
  S3" mas abajo para el detalle fino de por que esto casi no funciona.
  Terraform solo crea el repo vacio; el `docker push` es manual (ver abajo).
- **Secrets Manager** (`secrets.tf`): JWT secret (lo comparten GoTrue y
  PostgREST, uno firma, el otro valida) y credenciales del rol
  `authenticator` que usa PostgREST -- **no** el master de Aurora. Las URLs
  de conexion completas (`postgres://...`) se arman aca mismo con
  `jsondecode()` del secreto de Aurora de Fase 1, nunca se repite la
  password del master a mano.
- **ECS Fargate** (`ecs.tf`): un cluster, una task definition y un service
  por cada servicio (GoTrue 9999, PostgREST 3000). `256` CPU / `512` MB cada
  uno (minimo de Fargate) -- es el clon, sin trafico real. `lifecycle.ignore_changes = [desired_count]`
  en los dos services porque quien manda en el numero de tareas despues del
  primer apply es el auto-scaling (`autoscaling.tf`), no Terraform.
- **ALB** (`alb.tf`): **un solo** ALB, pero con **2 listeners HTTP** (puerto
  80 -> PostgREST, puerto 8081 -> GoTrue) en vez de 1 listener con reglas por
  path. Motivo: un ALB comun no reescribe el path de un pedido -- eso lo hace
  Kong en el Supabase real (`/auth/v1/token` -> le saca el prefijo y se lo
  manda a GoTrue en `/token`). Replicar Kong esta fuera de alcance de este
  clon (igual que answer_sheets/OCR), asi que se separa por **puerto** en vez
  de por path. Sin HTTPS todavia -- no hay dominio propio (llega en Fase 3
  con Amplify/CloudFront), y ACM gratis necesita un dominio real para validar
  el certificado. `network.tf` de Fase 1 se actualizo con ingress 80/8081 en
  `sg-alb` para esto (443 sigue preparado para cuando haya dominio).
- **S3** (`s3.tf`): un bucket privado para archivos. Sin servicio
  intermedio tipo "storage-api" de Supabase -- las apps Next.js (Fase 3) le
  hablan directo via SDK, fuera de alcance de este clon.
- **Auto-scaling** (`autoscaling.tf`): un target tracking por servicio,
  CPU al 60%, min 1 / max 3 tareas. Es lo que la prueba de carga de Fase 5
  tiene que grabar reaccionando en vivo.

### Roles de Postgres que hacen falta (`db/post-gotrue-roles.sql`)

Supabase Cloud los crea solos al armar un proyecto nuevo -- aca no, hay que
correrlos a mano UNA VEZ (mismo patron que `db/post-gotrue-fks.sql`):
`anon`, `authenticated`, `service_role` (los 3 "modos" con los que PostgREST
puede atender un pedido segun el JWT) y `authenticator` (el rol con el que
PostgREST se conecta de verdad, con la password que genero Terraform en
`secrets.tf`). Sin esto, PostgREST arranca pero falla cada conexion con
"role authenticator does not exist".

### Como se aplico en la practica (2026-10-16/17)

El plan original era un apply en 2 pasos (ECR+secretos primero, el resto
despues) para esquivar que un ECS service con `desired_count >= 1` no
termine de aplicar si la imagen no existe todavia. En la practica no hizo
falta: `aws_ecs_service` tiene `wait_for_steady_state = false` por default
en el provider de AWS -- el `apply` completo (38 recursos, incluidos los 2
services) termino en segundos sin esperar a que las tareas levantaran de
verdad. Terraform no avisa si las tareas de adentro fallan despues; hay que
revisarlo aparte (`aws ecs describe-tasks` / CloudWatch Logs).

Orden real que se siguio:
1. `terraform apply` completo (los 38 recursos, sin `-target`).
2. `docker login` a ECR + `docker pull` / `tag` / `push` de las imagenes
   oficiales a cada repo. Ojo: `supabase/gotrue` **no tiene tag `:latest`**
   en Docker Hub, solo versiones (`v2.187.0` funciono) -- se sube con el tag
   real de origen pero se **re-etiqueta a `:latest` en ECR** (el tag de ECR
   es independiente del de Docker Hub). `postgrest/postgrest:latest` si
   existe.
3. `db/post-gotrue-roles.sql` contra la base, via CloudShell (mismo patron
   que `db/schema.sql` en Fase 1 -- acceso temporal, ver abajo).

### El hallazgo del egress de S3 (2026-10-16/17)

GoTrue no lograba bajar su imagen: `CannotPullContainerError`, timeout al
conectarse a IPs que, a simple vista, parecian publicas y ajenas a la VPC.
Primer diagnostico (equivocado): se sospecho que el VPC Endpoint `ecr.dkr`
no resolvia bien por DNS privada -- se descarto `enableDnsSupport`/
`enableDnsHostnames` de la VPC, DHCP options, la asociacion de la zona
privada de Route 53, Resolver Rules y DNS Firewall (todo OK), se probo
borrar y recrear el endpoint (sin mejora real), y se llego a mover
`aws_ecs_service.gotrue`/`.postgrest` a subred publica con IP publica como
workaround -- **revertido** al encontrar la causa real.

**Causa real:** las IPs del error (verificadas contra el `ip-ranges.json`
oficial de AWS) son de **S3**, no de ECR. ECR no guarda las capas de las
imagenes el mismo -- las guarda en un bucket S3 (`prod-us-east-2-starport-
layer-bucket`) y redirige ahi cuando Fargate pide bajarlas. El Gateway
Endpoint de S3 (ya armado desde Fase 1) solo cambia el **ruteo** de ese
trafico para que nunca salga de la red de AWS -- el **destino** sigue
siendo una IP publica de S3, el DNS no cambia. `sg-servicios` tenia el
egress limitado a `10.0.0.0/16` (solo adentro de la VPC), asi que
bloqueaba exactamente esas IPs: por eso `ecr.dkr` SI funcionaba (resolver
el tag `:latest` al digest de la imagen, que se ve en el error mismo, ya
requeria haber hablado bien con el VPC Endpoint) pero bajar las capas
nunca llegaba a buen puerto.

**Fix real, sin moverse de subred privada:** `sg-servicios` (`network.tf`)
gano un egress acotado a la **prefix list de S3**
(`aws_vpc_endpoint.s3.prefix_list_id` -- una lista de rangos de IP que AWS
arma y mantiene sola, no "todo Internet"), puerto 443. `ecs.tf`
(`terraform/supabase-propio/`) volvio a subred privada, sin IP publica,
tal cual el diseno original -- el pivot a subred publica no hacia falta.

**Leccion para el video:** un Gateway Endpoint (S3, DynamoDB) resuelve el
*ruteo*, no el *destino* -- el security group lo sigue evaluando contra
las IPs reales del servicio. Es una distincion que vale la pena explicar:
mucha gente arma el VPC Endpoint y da por sentado que "ya no hace falta
tocar el security group", y no es asi.

**Efecto colateral bueno:** como se volvio a subred privada, los VPC
Interface Endpoints de Fase 1 (`ecr.api`, `ecr.dkr`, `secretsmanager`,
`logs`) terminaron usandose de verdad -- no quedo nada pagado sin
proposito.

### GoTrue necesitaba el rol `postgres` (2026-10-17)

Con el pull ya arreglado, GoTrue arrancaba pero moria en bucle: una
migracion propia (`20240612123726_enable_rls_update_grants`) asume que
existe un rol de Postgres llamado literalmente `postgres` (la convencion
real de Supabase -- el superusuario de cualquier proyecto Supabase se
llama asi siempre). Esta base usa `academia_premier_admin` como master
(decision de Fase 1), asi que ese rol nunca existio. Fix: `create role
postgres;` (sin login, sin ser superusuario -- la migracion solo le
otorga SELECT con grant option sobre las tablas de `auth`), nuevo script
`db/gotrue-postgres-role.sql`. Con eso GoTrue corrio sus 19 migraciones
solo y quedo arriba (`GoTrue API started on: 0.0.0.0:9999`).

### La password del `authenticator` no coincidia (2026-10-17)

Con GoTrue arriba, PostgREST fallaba con `password authentication failed
for user "authenticator"`. Causa: un error de transcripcion mio (Claude)
leyendo una captura de pantalla con la password generada por Terraform --
lei `...By8P...` (ocho) donde en realidad decia `...ByBP...` (be), son
muy parecidos en esa fuente. `db/post-gotrue-roles.sql` se habia corrido
con el valor mal transcripto, asi que el rol en la base nunca coincidio
con el secreto real que usa `secrets.tf`. Fix: `ALTER ROLE authenticator
WITH PASSWORD '...'` contra el valor REAL, pescado fresco de Secrets
Manager (nunca retipeado a mano, copiado/pegado directo del comando).

**Leccion:** cuando una password larga se transcribe a mano (de una
captura, de memoria, etc.), un solo caracter mal leido rompe todo sin dar
ningun error claro al momento de "crear" -- `CREATE ROLE` no valida que
la password sea la correcta, solo la guarda. El error aparece recien
despues, en quien intenta loguearse con el valor real. Mejor habito:
siempre copiar/pegar el valor fresco de Secrets Manager en el momento de
usarlo, nunca reescribirlo de una nota o una lectura visual.

### Fase 2: COMPLETA Y VERIFICADA (2026-10-17)

GoTrue y PostgREST corriendo, ambos en subred privada (diseno original),
autenticados contra la base real, respondiendo atras del ALB:
- `curl http://<alb-dns>:8081/health` -> `{"version":"v2.187.0","name":"GoTrue",...}`
- `curl http://<alb-dns>:80/` -> 200 OK, esquema OpenAPI completo (137KB)

Pendiente real de Fase 2: ninguno.

### Datos de prueba cargados (2026-10-17)

`scripts/seed/generar_datos.py` corrido contra la base real -- 5
academias, 30.000 alumnos, 100 personal (directores/admin_sede/docentes/
tutores), 30.100 usuarios en `auth.users` via GoTrue. Password de prueba
para todos: `Demo1234!`. Corrido desde CloudShell (`subnedprime`), con los
paquetes de Python (`psycopg2-binary`, `Faker`, `bcrypt`) preparados en la
pestaña normal (con salida a Internet) y pasados por el bucket S3, porque
`subnedprime` no tiene ni `pip install` ni Upload file.

Fase 0 y Fase 2 completas del todo. Sigue Fase 3 (desplegar las apps
Next.js y apuntarlas a la nueva URL).

## Fase 3 -- en curso (2026-10-17, arrancada de madrugada)

**El plan:** `Proyecto_Full_Stack2.0` (las 5 apps reales) no vive en este
repo -- se clona aparte, en una rama local que **nunca se pushea** al
repo real (`aws-clon-fase3`, nunca toca `main` ni `produccion`). El
codigo de las apps **no se modifica**: usan el cliente oficial de
Supabase (`@supabase/ssr`), que asume una sola URL con `/auth/v1/...` y
`/rest/v1/...` -- justo lo que CloudFront ya resuelve (ver mas abajo).
Alcanza con apuntar `NEXT_PUBLIC_SUPABASE_URL` a CloudFront.

### CloudFront como reemplazo de Kong

Problema real, encontrado en el camino: Amplify sirve por HTTPS
obligatorio, y una pagina HTTPS no puede llamar a una API HTTP (mixed
content) -- el ALB es HTTP puro (sin dominio propio para un certificado).
Ademas, el cliente de Supabase arma `<url>/auth/v1/...` y
`<url>/rest/v1/...` esperando que algo (Kong, en el Supabase real) le
saque el prefijo antes de reenviar a GoTrue/PostgREST.

Solucion: `terraform/supabase-propio/cloudfront.tf`. Una distribucion de
CloudFront con 2 origins (GoTrue y PostgREST, ambos puertos del mismo
ALB) y 2 CloudFront Functions:
- **`quitar_prefijo`** (viewer-request): saca `/auth/v1` y `/rest/v1` del
  path antes de reenviar. Ademas corta el preflight CORS (`OPTIONS`)
  directo en el borde, sin llegar a los contenedores.
- **`agregar_cors`** (viewer-response): le agrega
  `Access-Control-Allow-Origin` a la respuesta real. Sin esto el
  navegador bloqueaba el login con "No 'Access-Control-Allow-Origin'
  header is present" -- GoTrue/PostgREST solos no agregan ese header, en
  el Supabase real lo pone Kong.

Las dos funciones reflejan **cualquier origen** que pida, en vez de una
lista fija -- simplificacion a proposito (5 apps, cada una en su puerto
en localhost y despues su propio dominio de Amplify; sin esto habria que
mantener una lista larga). Documentado como trade-off de seguridad
valido para un clon de portfolio sin datos reales, no como descuido.

URL de la API: `terraform output api_url` (carpeta `supabase-propio`).
Las claves `anon`/`service_role` NO son random -- son JWT firmados con el
mismo secreto que usan GoTrue/PostgREST (`scripts/generar-claves-jwt.py`,
sin dependencias, con modo de un solo token para evitar que copiar/pegar
un string largo a mano corrompa la firma).

### El login real funciono (2026-10-17)

Despues de los hallazgos de las secciones anteriores (CORS, el rol `postgres`,
las columnas de texto NULL en `auth.users`), **un director generado por el
seed entro al dashboard real**, autenticado por GoTrue en AWS. Primer login
de punta a punta: navegador -> CloudFront -> ALB -> GoTrue -> RDS -> JWT de
vuelta -> dashboard renderizado con la sesion real.

Usuario de prueba: `millacecilia@example.net` / `Demo1234!` (director, sacado
en vivo con `curl` + la clave `service_role` contra PostgREST, sin tocar la
base directo -- ver `scripts/generar-claves-jwt.py`).

### El siguiente hallazgo: RDS se quedo sin creditos de CPU

Con el login funcionando, el dashboard cargaba vacio ("0 alumnos" con 30.000
reales en la base) -- `504 Gateway Timeout` en casi todos los pedidos a
PostgREST. Los logs mostraban `PGRST003: Timed out acquiring connection from
pool` en bucle, hasta en el health check del propio ALB.

Causa confirmada con metricas reales (consola RDS -> Monitoring):
**`CPUCreditBalance` en 0** desde las 19:30, **`CPUUtilization` pegado al
99%** desde ese mismo momento. `db.t4g.micro` es una instancia *burstable*:
tiene un pozo limitado de creditos de CPU, y toda la actividad de la sesion
(cargas de esquema, 30.100 filas del seed, consultas repetidas) lo vacio.
Una vez en cero, el rendimiento cae al minimo garantizado -- muy poco para
atender ~10-15 pedidos en paralelo que dispara el dashboard al cargar.

**Primer intento de fix (fallo):** `db.t4g.micro` -> `db.t4g.small`. La
cuenta lo rechazo con `FreeTierRestrictionError: This instance size isn't
available with free plan accounts` -- **tercera restriccion confirmada** de
esta cuenta "Ready Set Build" (las otras dos: Aurora sin VPC propia, sin
SSO). Revertido a `db.t4g.micro` en `variables.tf`. Queda igual
`apply_immediately = true` en `aws_db_instance.db` (util para futuros
cambios de verdad permitidos, sin esperar ventana de mantenimiento).

**Fix real (gratis): indices.** `db/schema.sql` **no tenia ni un solo
indice** -- ni en `academia_id` (la columna que las 88 policies de RLS
revisan en CADA fila, via `mi_academia()`), ni en ninguna FK. Con 30.000
alumnos, cada consulta forzaba un recorrido completo de la tabla. Un indice
no consume CPU extra (es espacio en disco, centavos) -- mas barato y mas
efectivo que subir el tamano de instancia, que ademas no esta permitido.
Nuevo script `db/indices-rendimiento.sql`: 21 indices en `academia_id` (uno
por tabla multi-tenant) + 2 en `user_id` (las funciones de auth,
`mi_puesto()`/`mis_salones()`, buscan por ahi en cada pedido) + 22 en
llaves foraneas usadas en JOINs (Postgres no crea indice automatico para el
lado "muchos" de una FK). Separado de `db/schema.sql` a proposito: ese
archivo es la foto exportada de la Supabase real, y si a produccion
tampoco le pusieron estos indices es un hallazgo aparte para Bryan, no
algo que este repo deba "arreglar" silenciosamente ahi.

Esto **confirma en vivo**, con metricas reales, algo que ya estaba anotado
como sospecha en `rds.tf` desde Fase 1: que `db.t4g.micro` no aguantaria el
escenario real de 30k alumnos -- y de paso encontro un problema de verdad
(la falta de indices) que estaba ahi desde el principio, no solo en este
clon. Buen material para el video: no es una suposicion, es una prueba con
numeros, y la cuenta "Ready Set Build" ya va 3 veces sorprendiendo con
restricciones no documentadas de antemano.
