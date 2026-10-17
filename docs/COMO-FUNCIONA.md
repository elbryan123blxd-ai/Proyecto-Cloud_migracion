# Cómo funciona este proyecto

Guía completa del clon de Academia Premier sobre AWS: qué se construyó, por qué, y cómo
funciona cada pieza. Escrita para que se entienda sin saber AWS de antes.

Sirve para tres cosas:
1. **Repasar** lo que se hizo, en orden, sin releer el historial.
2. **Base del guion del video** — la sección final propone una estructura.
3. **Que alguien que entre al repo** (un reclutador, un compañero) entienda el proyecto
   en 15 minutos.

> Si buscás el estado operativo del día a día (qué falta, qué falló, decisiones
> abiertas), eso vive en [`../CLAUDE.md`](../CLAUDE.md). Este documento explica **cómo
> funciona**, no **en qué anda**.

---

## 1. La idea en una frase

Academia Premier es un SaaS real que hoy corre sobre **Supabase + Vercel**. Este proyecto
reconstruye esa misma plataforma sobre **AWS puro**, con infraestructura como código, para
demostrar que se puede — sin tocar producción y sin un solo dato real.

### Qué se reemplazó por qué

| En Supabase/Vercel | En AWS | Por qué |
|---|---|---|
| Postgres gestionado | **RDS PostgreSQL** | Mismo motor, gestionado por AWS |
| Supabase Auth | **GoTrue** (el mismo software, autohospedado) en ECS Fargate | Las políticas de seguridad de la base usan `auth.uid()`. Cambiar a Cognito las rompe todas |
| API autogenerada | **PostgREST** (el mismo software) en ECS Fargate | Igual que arriba: es la pieza real que usa Supabase por dentro |
| Kong (el router interno de Supabase) | **CloudFront + CloudFront Functions** | Ver sección 6 — es la parte más interesante del proyecto |
| Storage | **S3** | — |
| Hosting de las apps | **Amplify** (pendiente) | — |
| Variables de entorno | **Secrets Manager** | — |
| (nada equivalente) | **Terraform** | Todo reproducible y destruible con un comando |

**El punto clave:** no se reescribió la aplicación. Las 5 apps Next.js funcionan **sin
cambiarles una línea de código** — solo apuntándolas a una URL distinta. Eso es lo que
prueba que la migración es viable de verdad.

---

## 2. El recorrido, en orden

### Fase 0 — Fundaciones

Antes de crear nada que cueste plata:

- **Presupuesto con alarmas** ($50 y $100) — para que no haya sorpresas.
- **Acceso sin credenciales permanentes**: usuario IAM + MFA + sesiones temporales que
  vencen en horas (ver sección 8).
- **El esquema de la base exportado** de la Supabase real — solo estructura, cero datos:
  25 tablas, 21 funciones de permisos, 88 políticas de seguridad.
- **El generador de datos falsos** (`scripts/seed/generar_datos.py`): 5 academias, 30.000
  alumnos, 100 empleados. Todo inventado.
- **El "bootstrap" de Terraform**: un bucket S3 + una tabla DynamoDB para guardar el
  estado (ver sección 3).

### Fase 1 — Red y base de datos

La capa de abajo: VPC, subredes, firewalls, los "túneles privados" a los servicios de
AWS, la base RDS y el gestor de secretos.

Acá apareció **la primera sorpresa**: el plan original era Aurora Serverless v2 (que
escala a cero y no cobra cuando nadie la usa). El `terraform apply` falló: esta cuenta
del programa "Ready Set Build" **no permite crear Aurora dentro de una VPC propia** —
solo en modo "express", que la deja pública en internet y sin contraseña. Eso rompe el
pilar de seguridad del proyecto entero, así que se cambió a **RDS PostgreSQL normal**.
Se pierde el "escala a cero", se gana que la base sigue aislada.

Después se cargó el esquema contra la base real — y apareció **la segunda sorpresa**,
explicada en la sección 9.

### Fase 2 — El "Supabase propio"

GoTrue y PostgREST corriendo en contenedores, el balanceador de carga adelante, el
bucket S3, el auto-escalado. Acá aparecieron **tres problemas reales** (secciones 9.3,
9.4 y 9.5) que son, probablemente, lo más valioso para contar en un video: ninguno estaba
en ningún tutorial.

Al final de esta fase: `curl` a la API devuelve el esquema completo de las 25 tablas, y
GoTrue responde que está sano. Backend funcionando de verdad.

### Fase 3 — Las apps (en curso)

Conectar las 5 apps Next.js reales al backend nuevo. Acá apareció el problema más
interesante de todos (sección 6: por qué hizo falta CloudFront) y, al resolverlo, **el
login real funcionó**: un director generado por el seed entró al dashboard, autenticado
por GoTrue en AWS.

Pendiente: unos `504 Gateway Timeout` al traer datos, y publicar el frontend en Amplify.

---

## 3. Terraform, explicado desde cero

### Qué es

Terraform convierte **texto** en **infraestructura real**. Escribís un archivo que dice
"quiero una base de datos así", corrés un comando, y AWS la crea. Si borrás esas líneas y
volvés a correr, AWS la destruye.

La alternativa es hacer todo a mano clickeando en la consola de AWS. Funciona... hasta que
tenés que repetirlo, o recordar qué tocaste hace tres semanas, o borrar todo sin dejar
nada cobrando.

### Las cuatro piezas del lenguaje

```hcl
# 1. resource — CREA algo nuevo. El 90% de lo que vas a escribir.
resource "aws_vpc" "principal" {
  cidr_block = "10.0.0.0/16"
}

# 2. data — LEE algo que ya existe. Nunca lo crea ni lo modifica.
data "aws_cloudfront_cache_policy" "sin_cache" {
  name = "Managed-CachingDisabled"
}

# 3. variable — un parámetro configurable desde afuera.
variable "db_instance_class" {
  default = "db.t4g.micro"
}

# 4. output — un valor que este módulo le deja servido a otro.
output "vpc_id" {
  value = aws_vpc.principal.id
}
```

Y una quinta, `locals`, que son atajos internos para no repetir expresiones largas.

### El truco que hace que todo funcione: las referencias

```hcl
resource "aws_subnet" "privada" {
  vpc_id = aws_vpc.principal.id   # <-- esto
}
```

Esa línea hace dos cosas a la vez: dice *cuál* VPC usar, y le enseña a Terraform que **la
VPC tiene que existir primero**. Nunca le decís el orden: él lo deduce de las referencias
y arma un grafo de dependencias. Por eso un `apply` crea 38 recursos en el orden correcto
sin que nadie se lo indique.

### El estado (`terraform.tfstate`)

Terraform necesita recordar qué creó, para saber la próxima vez si tiene que crear,
modificar o borrar. Eso vive en un archivo de estado.

**Ese archivo guarda contraseñas en texto plano.** Por eso:
- Nunca se commitea (está en `.gitignore`).
- Vive en un bucket S3 cifrado (el "backend remoto").
- Una tabla DynamoDB hace de candado: si dos personas corren `apply` a la vez, la segunda
  espera en vez de pisar a la primera.

Eso es exactamente lo que crea `terraform/bootstrap/` — y tiene un problema de huevo y
gallina resuelto a propósito: **el bootstrap guarda su propio estado en el disco local**,
porque no puede guardar en el bucket el estado del bucket que todavía no existe.

### Cómo está organizado este repo

Tres módulos, cada uno con su propio estado, cada uno aplicable por separado:

```
terraform/
  bootstrap/          ← el bucket + la tabla del candado.  Estado: local
  red-y-base/         ← VPC, subredes, firewalls, RDS.     Estado: s3://…/red-y-base/
  supabase-propio/    ← ECS, ALB, CloudFront, S3, IAM.     Estado: s3://…/supabase-propio/
```

¿Por qué separados y no todo junto? Porque un error en la capa de arriba no debería poder
tocar la base de datos. Y porque un `plan` de 15 recursos se lee; uno de 60, no.

**Cómo hablan entre ellos:** el módulo de arriba *lee* los outputs del de abajo:

```hcl
data "terraform_remote_state" "red_y_base" {
  backend = "s3"
  config  = { bucket = "…", key = "red-y-base/terraform.tfstate", … }
}

# y después, en cualquier lado del módulo:
subnets = data.terraform_remote_state.red_y_base.outputs.subredes_privadas_ids
```

Nunca se copian IDs a mano. Si la VPC se recrea con otro ID, todo lo de arriba se entera solo.

### Los tres comandos

| Comando | Qué hace |
|---|---|
| `terraform init` | Baja los plugins y se conecta al backend. Una vez por carpeta |
| `terraform plan` | Dice **qué va a hacer**, sin hacer nada. Siempre leerlo |
| `terraform apply` | Lo hace, después de que confirmes con `yes` |

El `plan` siempre termina con la línea que importa:

```
Plan: 3 to add, 1 to change, 1 to destroy.
```

**Leer esa línea antes de confirmar es el hábito más importante de todos.** Un `destroy`
inesperado ahí es la diferencia entre un apply tranquilo y perder una base de datos.

---

## 4. Los servicios de AWS, uno por uno

Agrupados por para qué sirven, no por nombre.

### Para guardar datos

| Servicio | Qué es | Cómo se usa acá |
|---|---|---|
| **RDS PostgreSQL** | Una base Postgres administrada por AWS (backups, parches, etc.) | `db.t4g.micro`, la más chica. Vive en subred privada, sin IP pública. Nadie de internet la puede alcanzar |
| **S3** | Almacenamiento de archivos | Dos buckets: uno para el estado de Terraform, otro para los archivos de la app |
| **DynamoDB** | Base NoSQL | Una sola tabla, usada únicamente como candado de Terraform |
| **Secrets Manager** | Caja fuerte para contraseñas | Todas las credenciales. Ninguna está en el repo ni en una variable de entorno plana |

### Para correr código

| Servicio | Qué es | Cómo se usa acá |
|---|---|---|
| **ECS Fargate** | Corre contenedores sin que administres servidores | GoTrue y PostgREST, un servicio cada uno |
| **ECR** | Un registro privado de imágenes de Docker | Copia privada de las imágenes oficiales de GoTrue y PostgREST |
| **Application Auto Scaling** | Prende y apaga copias según la carga | Si el CPU pasa de 60%, levanta otra tarea (de 1 a 3) |

**Por qué Fargate y no Lambda:** GoTrue y PostgREST mantienen un *pool* de conexiones
abierto contra Postgres. En Lambda, cada copia abriría el suyo y agotaría la base. Además,
el pico documentado del producto real (30.000 alumnos marcando asistencia entre 7:30 y
7:45 AM) provocaría cientos de arranques en frío justo en el peor momento.

### Para repartir tráfico

| Servicio | Qué es | Cómo se usa acá |
|---|---|---|
| **ALB** (Application Load Balancer) | Reparte el tráfico entrante entre las copias que estén sanas | Un solo ALB, con dos puertas: 80 → PostgREST, 8081 → GoTrue |
| **CloudFront** | Red de distribución global (CDN) | Mucho más que un CDN acá: ver sección 6 |

### Para ver qué pasa

| Servicio | Qué es |
|---|---|
| **CloudWatch Logs** | Donde escriben los contenedores. Cada error de esta sesión se encontró acá |

### Para controlar quién puede qué

| Servicio | Qué es |
|---|---|
| **IAM** | Usuarios, roles y permisos. Ver sección 8 |

---

## 5. Networking, explicado con una analogía

Esta es la parte que más asusta. La analogía: **un barrio cerrado**.

### Las piezas

```
                           INTERNET
                              │
                        ┌─────┴─────┐
                        │    IGW    │  ← el portón, la única salida/entrada
                        └─────┬─────┘
    ┌─────────────────────────┼─────────────────────────┐
    │  VPC  10.0.0.0/16       │          (el barrio)    │
    │                         │                         │
    │   ┌─────────────────────┴──────────────────────┐  │
    │   │  SUBREDES PÚBLICAS   10.0.0.0/24, 10.0.1.0/24 │
    │   │  (tienen camino al portón)                 │  │
    │   │                  ALB                       │  │
    │   └────────────────────┬───────────────────────┘  │
    │                        │                          │
    │   ┌────────────────────┴───────────────────────┐  │
    │   │  SUBREDES PRIVADAS  10.0.10.0/24, 10.0.11.0/24│
    │   │  (NO tienen camino al portón)              │  │
    │   │     GoTrue    PostgREST    RDS             │  │
    │   │        │          │                        │  │
    │   │        └────┬─────┘                        │  │
    │   │       VPC Endpoints  ← túneles privados    │  │
    │   └────────────────────┬───────────────────────┘  │
    └────────────────────────┼──────────────────────────┘
                             ▼
                   ECR · S3 · Secrets Manager · CloudWatch
                   (servicios de AWS, sin pasar por internet)
```

| Pieza | En la analogía | En la realidad |
|---|---|---|
| **VPC** | El terreno cerrado del barrio | Tu red privada en AWS, con su rango de direcciones (`10.0.0.0/16` = 65.536 direcciones) |
| **Subred** | Una manzana del barrio | Un pedazo del rango. Cada una vive en una zona física distinta (AZ), para que si se cae un datacenter siga la otra |
| **Subred pública** | Manzana con calle al portón | Su tabla de rutas tiene una línea: "todo lo que no sea del barrio → al portón" |
| **Subred privada** | Manzana sin salida | Su tabla de rutas **no tiene** esa línea. No es que esté bloqueada: directamente no existe el camino |
| **Internet Gateway** | El portón | La única puerta entre la VPC e internet |
| **Tabla de rutas** | Los carteles de cada esquina | Dicen "para ir a X, agarrá por acá" |

### El NAT Gateway que NO usamos

El problema clásico: las cosas en subred privada (los contenedores) a veces necesitan
*salir* — por ejemplo, para bajar su imagen de Docker. La solución típica es un **NAT
Gateway**: un intermediario que hace los mandados afuera y trae la respuesta.

**Cuesta ~$32 al mes, prendido o no.** Para un proyecto con $160 de créditos, es un quinto
del presupuesto en una sola pieza. Así que se evitó, usando VPC Endpoints.

### VPC Endpoints: los túneles privados

Un VPC Endpoint es un camino directo desde tu subred privada hasta un servicio de AWS,
**sin pasar por internet**. Hay dos tipos, y la diferencia entre ellos causó uno de los
bugs más difíciles de este proyecto (sección 9.3).

#### Tipo 1: Interface Endpoint (ECR, Secrets Manager, CloudWatch Logs)

Crea una **tarjeta de red real** (una ENI) con una IP privada, dentro de tu subred. Y hace
un truco de DNS: el nombre público del servicio (`secretsmanager.us-east-2.amazonaws.com`)
pasa a resolver a esa IP privada en lugar de la pública.

```
Tu contenedor pregunta:  "¿dónde está secretsmanager.us-east-2.amazonaws.com?"
DNS de la VPC responde:  "en 10.0.11.43"   ← una IP de TU subred
```

Cuesta ~$7/mes cada uno. Hay 4 en este proyecto.

#### Tipo 2: Gateway Endpoint (S3)

**Es gratis**, pero funciona de una forma completamente distinta, y acá está el detalle que
rompe todo si no lo sabés:

```
Tu contenedor pregunta:  "¿dónde está S3?"
DNS responde:            "en 3.5.92.66"    ← una IP PÚBLICA. No cambia.
```

El Gateway Endpoint **no toca el DNS**. Lo que hace es agregar una línea a la tabla de
rutas: *"el tráfico que vaya a las IPs de S3, mandalo por este túnel en vez de por el
portón"*.

**Consecuencia que cuesta horas de debug:** el destino sigue siendo una IP pública, así que
el **firewall lo sigue evaluando como tráfico a internet**. Si tu regla de salida solo
permite `10.0.0.0/16`, S3 queda bloqueado — aunque el tráfico nunca salga de AWS.

Eso es exactamente lo que pasó acá (sección 9.3).

---

## 6. CloudFront: el reemplazo de Kong

Esta es, probablemente, **la decisión de arquitectura más interesante del proyecto**.

### El problema

Supabase, por dentro, no es un solo servidor: son varios (GoTrue para auth, PostgREST para
datos, Storage para archivos...). Pero vos, desde el código, usás **una sola URL**:

```js
const supabase = createClient('https://miproyecto.supabase.co', clave)
// y el cliente arma por dentro:
//   https://miproyecto.supabase.co/auth/v1/token    → GoTrue
//   https://miproyecto.supabase.co/rest/v1/alumnos  → PostgREST
```

Lo que reparte esos caminos se llama **Kong**, y hace tres trabajos:
1. Mira el path y decide a qué servicio mandarlo.
2. **Le saca el prefijo** antes de reenviar (GoTrue espera `/token`, no `/auth/v1/token`).
3. Le agrega los headers de CORS a la respuesta.

### Por qué el Load Balancer no alcanzaba

Un ALB sabe repartir por path... pero **no sabe reescribir**. Le llegaría `/auth/v1/token`
y se lo pasaría a GoTrue tal cual, que respondería `404` porque esa ruta no existe para él.

Por eso, en la Fase 2, se repartió **por puerto** (80 y 8081) en vez de por path. Funcionaba
para probar con `curl`, pero no servía para las apps reales, que asumen una sola URL.

### Y un segundo problema: HTTPS

El frontend se va a publicar en Amplify, que sirve **siempre por HTTPS**. Y un navegador
**bloquea** que una página HTTPS le hable a una API por HTTP (se llama *mixed content*).
Nuestro ALB es HTTP puro, porque un certificado necesita un dominio propio, que no tenemos.

### La solución: CloudFront + CloudFront Functions

CloudFront resuelve los dos problemas a la vez:

- **HTTPS gratis**, con su propio dominio (`algo.cloudfront.net`), sin dominio ni certificado.
- **Sí puede reescribir paths**, con funciones que corren en el borde.

```
                    ┌──────────────── CloudFront ────────────────┐
  Navegador ─HTTPS─►│                                            │
                    │  /auth/v1/* ─[saca el prefijo]─► ALB:8081 ─┼─► GoTrue
                    │  /rest/v1/* ─[saca el prefijo]─► ALB:80   ─┼─► PostgREST
                    │                                            │
                    │  OPTIONS (preflight) ─[responde acá mismo]─│
                    │  cualquier respuesta ─[agrega CORS]────────│
                    └────────────────────────────────────────────┘
```

Las dos funciones, de ocho líneas cada una:

- **`quitar_prefijo`** (antes de ir al origen): le saca `/auth/v1` o `/rest/v1` al path. Y
  si el pedido es un `OPTIONS` (el "permiso" que pide el navegador antes de un POST),
  **lo responde ahí mismo**, sin molestar a los contenedores.
- **`agregar_cors`** (después de que el origen respondió): le agrega el header que
  autoriza al navegador a leer la respuesta.

**Resultado: el código de las apps no se toca.** Se apunta `NEXT_PUBLIC_SUPABASE_URL` a la
URL de CloudFront y funciona igual que contra el Supabase real.

**Para el video, esta frase vale oro:** *"reemplacé Kong con CloudFront Functions"*.

---

## 7. El camino de un pedido, de punta a punta

Qué pasa exactamente cuando un director hace login y ve su dashboard:

```
 1. Navegador                POST https://…cloudfront.net/auth/v1/token
                             (email + contraseña)
         │
 2. CloudFront               la función saca "/auth/v1" → queda "/token"
         │
 3. ALB (puerto 8081)        lo manda a una tarea sana de GoTrue
         │
 4. GoTrue (ECS Fargate)     busca el usuario en auth.users
         │                   compara el hash de la contraseña
         │                   ▼
 5. RDS PostgreSQL           devuelve la fila del usuario
         │
 6. GoTrue                   arma un JWT FIRMADO con el secreto compartido
         │                   { "sub": "<id del usuario>", "role": "authenticated" }
         ▼
 7. Navegador                guarda ese JWT

 ── y después, para traer datos ──

 8. Navegador                GET https://…cloudfront.net/rest/v1/alumnos
                             Authorization: Bearer <el JWT>
         │
 9. CloudFront               saca "/rest/v1" → queda "/alumnos"
         │
10. ALB (puerto 80)          → PostgREST
         │
11. PostgREST                valida la FIRMA del JWT con el mismo secreto
         │                   lee el claim "role" → hace SET ROLE authenticated
         │                   traduce la URL a SQL: select … from alumnos
         ▼
12. RDS PostgreSQL           ⚠️ acá actúa RLS: las políticas comparan
                             auth.uid() (sacado del JWT) contra academia_id
                             y DEVUELVEN SOLO LAS FILAS DE SU ACADEMIA
```

**El paso 12 es el corazón de la seguridad de este producto.** No es el frontend el que
filtra por academia; es la base la que **se niega a devolver** las filas ajenas. Aunque la
app tuviera un bug, o alguien llamara a la API a mano con su propio token, la base no se
las entrega.

Y por eso la decisión de **no usar Cognito**: si la identidad no llega a Postgres como un
JWT que `auth.uid()` pueda leer, las 88 políticas de seguridad dejan de funcionar y hay
que reescribir la autorización entera en el código.

---

## 8. Seguridad: las capas, de afuera hacia adentro

La idea se llama **defensa en profundidad**: varias capas independientes, de modo que
fallar una no abre la puerta.

### Capa 1 — La red: no existe el camino

Los contenedores y la base viven en subredes **sin ruta a internet**. No es un firewall que
bloquea: es que el camino no está dibujado. La base además tiene `publicly_accessible =
false`: nunca tuvo una IP pública.

### Capa 2 — Los firewalls (Security Groups), encadenados

Un Security Group es un portero con dos listas: quién puede entrar, y a dónde puede salir.
La gracia es que **se referencian entre ellos**, no por IP:

```
  INTERNET ──► sg-alb ──► sg-servicios ──► sg-aurora
   (443,        (solo      (solo acepta      (solo acepta
   80, 8081)    acepta     tráfico que        5432 desde
                de inter-  venga del ALB)     sg-servicios)
                net)
```

Leído en voz alta: *"la base de datos solo acepta conexiones de los contenedores. Los
contenedores solo aceptan tráfico del balanceador. El balanceador es lo único que mira a
internet."* **Nadie se saltea un escalón.**

Además, `sg-aurora` y `sg-vpc-endpoints` tienen la salida **bloqueada a propósito**: una
base de datos nunca necesita iniciar una conexión hacia afuera. Si algún día lo intenta,
algo está muy mal — y no va a poder.

### Capa 3 — Las identidades (IAM): dos roles distintos

Una confusión muy común. Una tarea de ECS tiene **dos** roles, con trabajos diferentes:

| Rol | Quién lo usa | Para qué |
|---|---|---|
| **Execution role** | El *agente* de Fargate, **antes** de arrancar tu contenedor | Bajar la imagen de ECR, leer los secretos, escribir logs |
| **Task role** | Tu *código*, ya corriendo adentro | Hablar con otros servicios de AWS en tiempo de ejecución |

GoTrue y PostgREST no necesitan llamar a ningún servicio de AWS, así que su task role está
**vacío a propósito**. Y el execution role solo puede leer **los 4 secretos puntuales** de
este proyecto, listados por su ARN exacto — no "todos los secretos de la cuenta".

### Capa 4 — Los secretos: nunca en el código

Ninguna contraseña de este proyecto fue escrita a mano, nunca:

1. Terraform las **genera** (`random_password`).
2. Las guarda en **Secrets Manager**.
3. ECS las **inyecta** al contenedor al arrancar, pidiéndolas con el execution role.

El repo es público y no hay un solo secreto adentro. El archivo que sí los tendría
(`terraform.tfstate`) está en `.gitignore` y vive cifrado en S3.

Hay un detalle fino acá: GoTrue se conecta con el usuario maestro de la base, pero
**PostgREST no**. PostgREST usa un rol de bajo privilegio (`authenticator`) que ni siquiera
puede leer datos por sí mismo: solo puede "convertirse" en `anon` o `authenticated` según
lo que diga el JWT de cada pedido. Si PostgREST tuviera un bug, el daño está acotado.

### Capa 5 — Los datos: RLS en la base

Explicado en la sección 7, paso 12. Es la última línea, y la más fuerte: **aunque todas las
anteriores fallaran**, la base sigue sin devolver filas de otra academia.

### Capa 6 — El acceso humano: sin credenciales permanentes

Para trabajar contra AWS no se usa una clave fija:

```
usuario IAM + código MFA  →  aws sts get-session-token  →  credenciales que vencen en horas
```

Si esas credenciales temporales se filtran, el daño tiene fecha de vencimiento. (Durante
este proyecto se descubrió que el MFA figuraba como configurado en la documentación pero
**nunca se había creado de verdad** — se detectó y se armó. Ver sección 9.2.)

---

## 9. Los problemas reales (la mejor parte para el video)

Ningún tutorial tiene esto. Son los que de verdad enseñan.

### 9.1 — Las funciones que no se podían crear

**Síntoma:** al cargar el esquema, las 25 tablas entraron bien, pero casi todas las
funciones de permisos fallaban con `schema "auth" does not exist`.

**Causa:** las funciones usan `auth.uid()` (la función de Supabase que dice quién sos).
Pero son funciones `language sql`, y Postgres **valida que lo que referencian exista en el
momento de crearlas**, no al llamarlas. Como el schema `auth` lo crea GoTrue recién al
arrancar (Fase 2), nada se podía crear en la Fase 1.

**Solución:** crear `auth.uid()` nosotros mismos, con la **implementación real** que usa
Supabase (lee el claim `sub` del JWT). No es un parche temporal: sigue siendo correcta
cuando GoTrue se despliega después.

### 9.2 — El MFA que decía estar y no estaba

**Síntoma:** ninguno. La documentación decía "MFA activo ✅" desde la Fase 0.

**Causa:** alguien (yo) lo marcó como hecho sin verificarlo. Un `aws iam list-mfa-devices`
devolvió una lista vacía.

**Lección:** la documentación que no se verifica miente con confianza. Se armó de verdad
(por CLI, porque la consola ni siquiera mostraba la opción) y se corrigió el checklist.

### 9.3 — El contenedor que no podía bajar su imagen ⭐

El más difícil, y el mejor para contar.

**Síntoma:** `CannotPullContainerError`. La tarea no podía bajar la imagen de ECR, aunque
los VPC Endpoints de ECR estaban creados y "Available". Timeout contra una IP pública.

**Primera hipótesis (equivocada):** "la resolución DNS privada está rota". Se descartó
metódicamente: los flags DNS de la VPC, el DHCP option set, la zona privada de Route 53, las
Resolver Rules, el DNS Firewall. Todo correcto. Hasta se destruyó y recreó el endpoint.
Nada.

**El detalle que destrabó todo:** leer el error con más cuidado.

```
failed to copy: httpReadSeeker: … gotrue:latest@sha256:6ff0cda74c95…
```

Ese `sha256:6ff0cda…` era **exactamente el digest de la imagen que se había subido**. Para
saberlo, la tarea **tuvo que hablar con ECR y que le respondiera bien**. Los endpoints de
ECR funcionaban perfecto. Lo que fallaba era el paso siguiente.

**La causa real:** ECR no guarda las imágenes él mismo — **las guarda en S3** y redirige
ahí para bajar las capas. Y S3, por Gateway Endpoint, **conserva las IPs públicas como
destino** (sección 5). El firewall `sg-servicios` solo permitía salir hacia `10.0.0.0/16`,
así que bloqueaba exactamente esos paquetes.

Se confirmó cruzando las IPs del error contra el `ip-ranges.json` oficial de AWS: las siete
eran de **S3 us-east-2**.

**Solución:** una línea — permitir salida al *prefix list* de S3. Las tareas siguieron en
subred privada, como el diseño original.

> **La lección, en una frase:** un Gateway Endpoint cambia el **ruteo**, no el **destino**.
> El firewall lo sigue evaluando contra las IPs reales del servicio.

### 9.4 — El rol `postgres` que Supabase trae de fábrica

**Síntoma:** GoTrue arrancaba y se moría en bucle. Los logs: `role "postgres" does not
exist`.

**Causa:** una migración interna de GoTrue asume que existe un rol llamado literalmente
`postgres` — es la convención de Supabase, donde el superusuario siempre se llama así.
Nuestra base usa otro nombre.

**Solución:** `create role postgres;`. Tres palabras, después de leer el log correcto.

### 9.5 — Kong también hacía CORS

**Síntoma:** con CloudFront ya armado, el login fallaba en el navegador: *"No
'Access-Control-Allow-Origin' header is present"*. Pero con `curl` funcionaba perfecto.

**Causa:** `curl` no aplica las reglas de CORS; los navegadores sí. Kong, además de repartir
y reescribir, **agrega los headers de CORS**. Se había reemplazado solo dos de sus tres
trabajos.

**Solución:** una segunda CloudFront Function, en el evento de respuesta.

### 9.6 — Los 30.100 usuarios que GoTrue no podía leer

**Síntoma:** login con error 500: `Scan error on column "confirmation_token": converting
NULL to string is unsupported`.

**Causa:** el script de datos insertó los usuarios **directo por SQL**, sin pasar por la API
de GoTrue. Cuando GoTrue crea un usuario, deja varias columnas de texto en `''`; un INSERT
que no las menciona las deja en `NULL`. Y el código de GoTrue (en Go) no sabe leer `NULL`
ahí.

**Primer intento:** arreglar las seis columnas conocidas. Falló — apareció una séptima
(`email_change`) que no estaba en la lista.

**Segundo intento:** un bloque que recorre **todas** las columnas de texto y las arregla de
una. Falló también: la columna `phone` tiene restricción **UNIQUE**, y poner `''` en todas
las filas choca entre sí. Y como todo era una sola transacción, el error **deshizo también
lo que ya había funcionado**.

**Solución final:** el mismo recorrido, excluyendo las columnas con restricción `UNIQUE`.

> **La lección:** arreglar de a un caso te hace volver tres veces. Arreglar el *patrón*
> entero, una. Pero cuidado con los casos especiales dentro del patrón.

### 9.7 — El anti-patrón de Terraform que mordió tres veces

Los Security Groups de este repo declaran sus reglas **inline**. Un `aws_security_group` con
reglas inline se considera dueño de **todas** las reglas del grupo, y revoca lo que no esté
declarado ahí.

El acceso temporal a la base (para correr scripts a mano) se agregó como un recurso
**aparte**. Resultado:

1. **Ruido:** cada `plan` mostraba cambios fantasma en dos security groups.
2. **La regla se caía sola:** cualquier `apply` por otro motivo la revocaba.
3. **Un `apply` roto de verdad:** Terraform borró la regla con un recurso y acto seguido
   intentó borrarla otra vez con el otro → `InvalidPermission.NotFound`.

**La lección:** no mezclar los dos estilos de declarar reglas en un mismo security group.
Está documentado en `CLAUDE.md` para que no vuelva a pasar.

---

## 10. Qué cuesta, y por qué

Créditos disponibles: **$160**. Objetivo: ~$50/mes con todo prendido.

Las tres cosas que funden una cuenta de AWS sin avisar, y qué se hizo con cada una:

| Trampa | Costo típico | Qué se hizo acá |
|---|---|---|
| **NAT Gateway** | ~$32/mes | **No se usa.** VPC Endpoints en su lugar |
| **Varios Load Balancers** | ~$17/mes c/u | **Uno solo**, compartido entre los dos servicios |
| **Base sobredimensionada** | $13 a $400/mes | La instancia más chica (`db.t4g.micro`) |

Lo que sí se paga: la base (~$13/mes), el ALB (~$17/mes), los 4 Interface Endpoints (~$7/mes
c/u) y Fargate (~$10/mes con dos tareas chicas). CloudFront, en este volumen, entra en el
*free tier* perpetuo: $0.

**Honestidad importante para el video:** `db.t4g.micro` (1 GB de RAM) **no aguantaría** el
escenario real de 30.000 alumnos marcando asistencia a las 7:45 AM. Alcanza para el clon,
que no tiene tráfico. Saber esa diferencia —y decirla— vale más que fingir que sí.

---

## 11. Guion sugerido para el video

Una estructura posible, de ~12 a 15 minutos. La idea es **contar un problema y su
solución**, no recorrer la consola de AWS servicio por servicio.

### Apertura (1 min) — El problema, no la tecnología
> "Tengo un SaaS real funcionando en Supabase, con academias pagando. Quise saber si podía
> reconstruirlo entero sobre AWS, sin reescribir la aplicación. Spoiler: se puede, y las
> apps no cambiaron ni una línea."

Mostrá el producto real funcionando primero. Que se vea que existe de verdad.

### Bloque 1 (2 min) — El mapa
El diagrama de la sección 5 o 7. Tres capas: el navegador, lo que corre en AWS, la base.
Sin entrar en detalle todavía.

### Bloque 2 (3 min) — Terraform
No expliques la sintaxis. Mostrá **el `plan`**, la línea `3 to add, 1 to change, 1 to
destroy`, y el `apply` creando 38 recursos en orden. Después mostrá que borrando líneas se
destruye. **Eso** es lo que impresiona: que la infraestructura es un archivo de texto.

### Bloque 3 (3 min) — Seguridad, de afuera hacia adentro ⭐
La cadena de la sección 8, en voz alta: *"la base solo acepta a los contenedores, los
contenedores solo al balanceador, el balanceador es lo único que ve internet"*.

Y el remate: **RLS**. Mostrá que aunque la API devuelva datos, Postgres se niega a entregar
filas de otra academia. Si podés, demostralo en vivo con dos usuarios de academias distintas.

### Bloque 4 (3 min) — El problema difícil ⭐⭐
**Esta es la parte que te diferencia.** Contá el bug de la sección 9.3 como una historia:

1. "El contenedor no podía bajar su imagen."
2. "Pensé que era DNS. Descarté cinco cosas, una por una."
3. "Hasta que leí bien el error: traía el digest de la imagen. Entonces ECR SÍ respondía."
4. "ECR guarda las capas en S3. Y S3 por Gateway Endpoint usa IPs públicas: el firewall las
   bloqueaba."
5. "Lo confirmé cruzando las IPs contra el archivo de rangos oficial de AWS."
6. "Una línea de arreglo."

Eso muestra **método de diagnóstico**, que es lo que de verdad se contrata.

### Bloque 5 (2 min) — Kong y CloudFront
"Supabase usa Kong por dentro para repartir una sola URL entre varios servicios. Yo no
tenía Kong. Lo reemplacé con CloudFront Functions: ocho líneas de JavaScript corriendo en
el borde." Mostrá la función.

### Cierre (1 min) — Honestidad
Qué quedó pendiente, qué no aguantaría producción real y por qué, y qué costó.

**Terminar admitiendo los límites genera más confianza que terminar diciendo que todo es
perfecto.**

---

## 12. Lo que falta

| Pendiente | Dónde |
|---|---|
| Los `504 Gateway Timeout` al traer datos | En curso |
| Publicar el frontend en Amplify | Fase 3 |
| CI/CD con GitHub Actions + OIDC | Fase 4 |
| Dashboard y alarmas en CloudWatch | Fase 5 |
| La prueba de carga (el "clip épico" del video) | Fase 5 |
| `terraform destroy` y verificar que no quede nada cobrando | Fase 5 |

El detalle actualizado de cada uno vive en [`PLAN.md`](PLAN.md) y en
[`../CLAUDE.md`](../CLAUDE.md).
