# Operación de la réplica

## Antes de desplegar

- Confirmar la cuenta de práctica definitiva, región permitida y presupuesto.
- Acceder con rol/sesión temporal. El acceso histórico se describe en la bitácora,
  no debe asumirse que sigue vigente.
- Los backends S3 son parciales y se generan desde el bootstrap nuevo por entorno.
  Seguir [terraform/environments](../terraform/environments/README.md); no reutilizar el
  bucket ni migrar automáticamente el estado del proyecto anterior. Un backend nuevo implica
  estado nuevo o migración explícita; no aplicar estado vacío sobre recursos existentes.
- No renombrar recursos Terraform `aurora_*` solo por claridad. Planificar `moved`/migración
  de estado si se realiza una refactorización futura.
- Confirmar versiones PostgreSQL e imágenes disponibles y subir imágenes a ECR. `latest`
  es el valor histórico: fijar versión/digest antes de una demo reproducible.

## Validación y orden

```powershell
terraform fmt -check -recursive terraform

terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap validate
terraform -chdir=terraform/bootstrap plan
```

Revisar/aplicar bootstrap; generar los backends con `scripts/terraform/Preparar-Backend.ps1`
y seguir los comandos con `-backend-config` y `-var-file` del entorno en
[terraform/environments](../terraform/environments/README.md).
Cada módulo tiene su propio estado. El output
`db_instance_id` debe publicarse aplicando base antes del plan de servicios.

Para validación local sin backend se puede usar `init -backend=false` y `validate`.
Esto descarga proveedores, pero no sustituye el plan con estado y credenciales reales.

### Primer despliegue: pasos que Terraform no resuelve solo

El historial de orden real está en [CLAUDE.md](../CLAUDE.md#como-se-aplico-en-la-practica-2026-10-1617).
El flujo debe coordinar recursos, imágenes y migraciones:

1. Base/red disponibles; acceso SQL temporal y privado con permisos acotados.
2. Revisar/cargar `db/schema.sql`, incluido `auth.uid()`, y preparar el rol requerido por GoTrue
   con `db/gotrue-postgres-role.sql`.
3. Crear repositorios/secretos/servicios y publicar las imágenes. Un apply exitoso no prueba
   que las tareas tengan imágenes disponibles ni hayan alcanzado estado saludable.
4. GoTrue debe completar sus migraciones antes de aplicar scripts que dependen de `auth.users`.
5. Revisar/aplicar `post-gotrue-roles.sql`, `post-gotrue-fks.sql` e `indices-rendimiento.sql`
   según sus dependencias. La contraseña de `authenticator` debe coincidir con Secrets Manager,
   sin transcribirla ni guardarla en archivos versionados.
6. Seed y validación siguiendo [scripts/seed/README.md](../scripts/seed/README.md).
7. Cerrar todo acceso SQL temporal, volver a ejecutar plan y verificar ausencia de reglas residuales.

No ejecutar scripts correctivos `fix-*` indiscriminadamente: verificar si aplica su condición.
Las migraciones SQL todavía no tienen un pipeline idempotente completo.

## Proyecto nuevo · revisión 23 NOV 2026

El cambio añade subredes de datos y nombres por entorno; se prepara para el proyecto
`519119252721`, no como actualización in situ del despliegue histórico. Inventario inicial
sin infraestructura de la réplica en los servicios consultados. El plan del proyecto no pudo
identificarse: `GetAccountPlanState` devolvió `ResourceNotFoundException: Missing data`.
Confirmarlo en AWS Settings > Billing antes del despliegue.

Los puntos siguientes describen el procedimiento histórico de la revisión de SG, no el
plan de creación desde cero del proyecto nuevo:

1. Revisar cambios de SG en plan de `red-y-base`; deben ser actualizaciones de reglas,
   no reemplazos de VPC, base o subredes.
2. Aplicar base, verificar publicación de `db_instance_id`.
3. Plan de servicios: dashboard nuevo y alarmas solo si se configuran.
4. Aplicar y validar auth, consultas, acceso S3/ECR, logs y dashboard.
5. Si el cambio de egress bloquea una dependencia, identificar destino/puerto real y ajustar
   de forma acotada. El egress actual cubre PostgreSQL, endpoints HTTPS y S3; no Internet general.

## Pruebas funcionales y de capacidad

Comprobar salud GoTrue, consultas autorizadas, matriz multi-tenant, sesiones vencidas,
escrituras e integridad. No usar `service_role` para demostrar aislamiento RLS.

Para carga, especificar porcentaje de login vs lectura/escritura, requests por flujo,
concurrencia, duración de oleadas y datos sintéticos. Generar tráfico desde un entorno
capaz y autorizado. Empezar con baseline y aumentar gradualmente hasta el objetivo.
Registrar límites del generador y del sistema, errores, p95/p99, pools y comportamiento del escalado.

## Backups y restauración

Estado actual: backup RDS de un día, Single-AZ, sin protección de borrado y sin snapshot
final obligatorio. Es una decisión de entorno destruible; no una política de producción.

Prueba pendiente:

1. Registrar hora de una escritura sintética de referencia.
2. Seleccionar backup/PITR disponible y restaurar en una instancia aislada con identificador distinto.
3. Validar datos, esquema, roles y RLS, sin reemplazar el origen de la aplicación.
4. Medir tiempo de recuperación y antigüedad de los datos recuperados.
5. Eliminar recursos de la prueba cuando termine y revisar costos.

Registrar RTO/RPO **medidos**; no prometer objetivos sin esta prueba.

## Rollback y limpieza

Guardar plan revisado y versiones de imágenes. Para cambios de SG, revisar el diff inverso y
restaurar solo reglas necesarias si un flujo falla. Para app, volver a task definition/imagen
conocida; una migración de DB no se revierte automáticamente al cambiar un contenedor.

Destruir en orden inverso: servicios, red/base y finalmente bootstrap. Antes, decidir si hay
evidencia/snapshots que conservar y proteger el estado. Buckets versionados, repos ECR con
imágenes, distribución CloudFront, secretos en ventana de recuperación y snapshots pueden
impedir destrucción o dejar recursos/costos residuales. Un `destroy` no garantiza factura cero.

## Evidencia por ejecución

Registrar fecha, cuenta de práctica identificada sin secretos, commit, región, plan revisado,
checks realizados, métricas y costo estimado. No marcar el despliegue como actual usando solo
capturas o anotaciones históricas.
