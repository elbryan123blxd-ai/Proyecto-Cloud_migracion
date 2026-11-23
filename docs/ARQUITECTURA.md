# Arquitectura de la réplica

## Topología del código

### Objetivo acordado · 23 NOV 2026

[Ver diagrama actualizado PNG](arquitectura-objetivo.png).

La nueva vista es **un diseño objetivo por entorno**. La red y la separación de estados
ya están codificadas; el conjunto del objetivo aún no está implementado ni desplegado.
Define seis subredes distribuidas entre dos AZ:

| Capa | AZ A | AZ B |
|---|---|---|
| Pública / ALB | `10.0.0.0/24` | `10.0.1.0/24` |
| Privada aplicación / ECS y ENI de endpoints | `10.0.10.0/24` | `10.0.11.0/24` |
| Privada datos / RDS | `10.0.20.0/24` | `10.0.21.0/24` |

Los CIDR de datos son propuestos y deben comprobarse contra el inventario y el plan.
La vista Multi-AZ representa principal y standby RDS clásico; la aplicación utiliza el
endpoint de conexión, no consulta directamente el standby. También ilustra al menos dos
tareas por servicio distribuidas para validar disponibilidad. Dev comienza con una tarea
por servicio y RDS Single-AZ; preprod/prod permiten comprobar temporalmente Multi-AZ.
Cada entorno tendrá sus propios recursos y estado. Las pruebas se realizarán por turnos
con un presupuesto total de USD 120, incluyendo costos residuales.

Las notificaciones internas se almacenarán en PostgreSQL, con RLS y estado de lectura.
El navegador las consultará vía PostgREST al entrar y periódicamente mientras la app esté
visible; pausará las consultas al ocultarse o cerrarse. Frecuencia por definir y medir.
La generación requiere lógica SQL o un servicio propio. Este flujo no incorpora SNS,
SQS, EventBridge ni push en segundo plano. SNS se conserva en el objetivo de alertas de gasto.

Se muestran rotación mediante Secrets Manager/Lambda y renovación coordinada de tareas,
roles separados, observabilidad y control de costos como trabajo pendiente. El dominio
CloudFront se mantiene para pruebas; el código aún utiliza HTTP al ALB. Dominio propio,
certificado y TLS al origen forman parte de la evolución posterior.

### Configuración actual del repositorio

Región configurada: `us-east-2`. VPC `10.0.0.0/16` en dos AZ seleccionadas por Terraform.
No se fijan nombres como `us-east-2a`: las asignaciones se leen de la cuenta.

| Capa | Ubicación | Componentes |
|---|---|---|
| Entrada global | Fuera de la VPC | CloudFront y Functions; WAF pendiente |
| Entrada regional | Públicas `10.0.0.0/24`, `10.0.1.0/24` | ALB internet-facing |
| Servicios | Privadas `10.0.10.0/24`, `10.0.11.0/24` | ECS Fargate GoTrue/PostgREST |
| Datos | Privadas `10.0.20.0/24`, `10.0.21.0/24`, subnet group en dos AZ | RDS Single-AZ en dev; Multi-AZ configurable |
| Acceso privado AWS | ENI en ambas privadas | ECR API/DKR, Secrets Manager, Logs |
| Almacenamiento regional | Fuera de la VPC | S3 y Secrets Manager; S3 gateway en rutas privadas |
| Operación | Control plane AWS | CloudWatch; GuardDuty y CloudTrail pendientes |
| IaC | Fuera del runtime | Terraform, estado S3 y lock DynamoDB |

La tabla pública tiene ruta `0.0.0.0/0 → IGW`. La privada de aplicación tiene ruta local y
la ruta de S3 mediante gateway endpoint; la tabla de datos tiene solo la ruta local.
No hay NAT ni ruta privada por defecto hacia Internet.
La NACL predeterminada permanece asociada a las subredes.

## Flujo de una solicitud

1. El navegador llama a CloudFront por HTTPS con su JWT si corresponde.
2. El comportamiento `/auth/v1/*` elige GoTrue; `/rest/v1/*` elige PostgREST.
3. Una Function retira el prefijo. La API tiene caché deshabilitada.
4. CloudFront usa actualmente HTTP hacia ALB: 8081 para auth, 80 para REST.
5. ALB reenvía a GoTrue :9999 o PostgREST :3000 en tareas privadas.
6. PostgREST valida JWT y establece el contexto del rol/claims en PostgreSQL.
7. Las políticas RLS y grants determinan las filas y operaciones permitidas.

GoTrue accede a la base para identidad y sesiones; no representa toda la autorización
de negocio. Los flujos de archivos S3 todavía requieren integración: crear un bucket
no reemplaza automáticamente la API Storage de Supabase.

## Alta disponibilidad: límite importante

Tener subredes y endpoints en dos AZ no significa tener el servicio altamente disponible.
En dev la base es Single-AZ y el mínimo actual es una tarea por servicio. No dibujar dos instancias
RDS ni una tarea fija en cada AZ como si ya existieran. La segunda AZ es elegible para
ubicación/escalado; distribución efectiva y failover deben probarse.

La separación de subredes de datos y aplicación está codificada desde el 23 NOV.
Está preparada para el proyecto nuevo con estados nuevos: no aplicar como migración
automática del proyecto anterior. Los nombres por entorno pueden reemplazar recursos viejos.

## Decisiones y correcciones técnicas

- Fargate es apropiado para GoTrue/PostgREST persistentes. No hay benchmark comparativo
  que permita afirmar equivalencia de costo con Lambda.
- Cognito puede integrarse con autorización en PostgreSQL mediante una adaptación adecuada.
  GoTrue se conserva para reducir cambios y mantener compatibilidad, no porque RLS lo exija.
- ALB incorpora capacidades de transformación de URL. La imposibilidad de reescribir paths
  descrita en la bitácora no debe tratarse como limitación vigente universal. Esta réplica
  conserva su diseño CloudFront/Functions hasta evaluar una migración con pruebas.
- Los endpoints Interface se cobran por AZ/hora y datos. Cuatro servicios en dos AZ representan
  ocho ubicaciones facturables, no cuatro. No asumir que cuestan menos que NAT en todo escenario.
- El gateway S3 modifica rutas; los destinos siguen siendo rangos S3. Se mantiene egress HTTPS
  a su prefix list para descargar las capas ECR.
- Un índice consume almacenamiento, CPU y trabajo de mantenimiento/escritura. Su beneficio
  depende de selectividad y patrón de consultas; validar con `EXPLAIN (ANALYZE, BUFFERS)`.
- RDS T4g usa comportamiento Unlimited: saldo de créditos en cero no prueba por sí solo
  limitación de CPU. Correlacionar créditos excedentes, CPU, consultas, I/O, locks y pool.

## Diagrama

Abrir [arquitectura-objetivo.png](arquitectura-objetivo.png): separación aplicación/datos,
Multi-AZ, notificaciones internas, rotación y presupuesto.

Los cuatro VPC endpoints Interface (ECR API, ECR DKR, Secrets Manager y CloudWatch Logs)
tienen una ENI por subred de aplicación: cuatro endpoints, ocho ENI en dos AZ.
ECS accede por HTTPS :443, con DNS privado habilitado y SG-endpoints que permite los
orígenes autorizados. Las políticas de endpoints y roles de ejecución limitan el acceso.
S3 Gateway no crea ENI y se asocia a las tablas de rutas de aplicación A/B; también permite
obtener las capas de imágenes de ECR. No se duplican endpoints en las subredes de datos.
El DNS de RDS es el nombre de conexión SQL de la base, no un VPC endpoint de PrivateLink.

Servicios globales/regionales se muestran fuera de las subredes; dentro se representan
las ENI de endpoints. El ALB central es un único recurso lógico asociado a las dos
subredes públicas mediante sus ENI. La vista objetivo representa el standby de Multi-AZ;
el código actual todavía declara Single-AZ.

## Fuentes de referencia

- [Reglas y transformaciones ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-rules.html)
- [RDS: clases de instancia](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.DBInstanceClass.Types.html)
- [RDS T4g y Unlimited](https://aws.amazon.com/rds/instance-types/)
- [CloudFront: protección de un origen ALB](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/restrict-access-to-load-balancer.html)
- [Precios PrivateLink](https://aws.amazon.com/privatelink/pricing/)

Las restricciones históricas de la cuenta Ready Set Build no se generalizan a todas las
cuentas ni planes. La disponibilidad de servicios/versiones se confirma antes del despliegue.
