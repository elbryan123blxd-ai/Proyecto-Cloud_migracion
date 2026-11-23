# Entornos del proyecto nuevo

Proyecto autorizado: `519119252721`. Region: Ohio (`us-east-2`). `main` es la rama de
preprod, no un cuarto entorno. Cada entorno usa recursos con nombres/etiquetas propios y
claves de estado separadas; los CIDR pueden repetirse porque son VPC independientes.

## Primera ejecucion

### Espacios de trabajo de VS Code

Abrir `DEV.code-workspace`, `PRE-PROD.code-workspace` o `PRODUCCION.code-workspace` desde
Archivo > Abrir area de trabajo desde archivo. Son vistas del mismo repositorio:
configuracion exclusiva del entorno y codigo comun de red, servicios, bootstrap, SQL,
scripts y documentacion. Editar codigo compartido afecta a los tres entornos.
La barra de titulo identifica el entorno con verde, ambar o rojo.

Ctrl+Shift+B ejecuta **Validar Terraform**. Terminal > Ejecutar tarea ofrece:

| Tarea | Funcion |
|---|---|
| Validar Terraform | Inicializa sin backend y valida los tres modulos |
| Comprobar formato | Comprueba formato, sin reescribir archivos |
| Pruebas locales (mocks) | Ejecuta las suites sinteticas de red y servicios, sin AWS |
| Plan bootstrap (compartido) | Inicializa y muestra el plan del backend comun |
| Preparar backend | Genera configuracion del entorno desde outputs de bootstrap ya aplicado |
| Plan red y base | Inicializa el backend del entorno y usa sus tfvars |
| Plan servicios | Usa su backend, sus tfvars y el bucket de estado generado |

Las tareas invocan `scripts/terraform/Ejecutar-Tarea.ps1`, usan el perfil
`cloud-migracion`, Ohio y el workspace Terraform `default`. Las vistas de VS Code no son
workspaces Terraform. Cada entorno/modulo tiene su `TF_DATA_DIR` aislado dentro de
`terraform/environments/<entorno>/.terraform`; validaciones y planes usan subdirectorios
distintos. Bootstrap conserva su directorio y estado local compartidos.
Ejecutar planes del mismo modulo/entorno de uno en uno.

Las tareas de planes requieren sesion AWS vigente y los backends generados; el plan de
servicios requiere ademas el estado de red ya aplicado. No hay tareas apply/destroy ni
ejecucion automatica al abrir el espacio. Las pruebas mock usan datos sinteticos: su
etiqueta de entorno identifica la vista, no una prueba de recursos desplegados de ese entorno.

### Comandos desde terminal

No usar ni migrar automaticamente el estado del proyecto anterior. Antes de inicializar,
verificar que no exista un `.terraform` o estado local previo en estos directorios.
El estado local de bootstrap debe conservarse y respaldarse de forma privada.

Desde la raiz del repositorio, con el perfil temporal del proyecto nuevo:

```powershell
$env:AWS_PROFILE = 'cloud-migracion'
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan -out=bootstrap.tfplan
# Revisar el plan antes de aplicar; este es el primer paso que crea recursos.
terraform -chdir=terraform/bootstrap apply bootstrap.tfplan

.\scripts\terraform\Preparar-Backend.ps1 -Environment dev

terraform -chdir=terraform/red-y-base init -reconfigure -backend-config=../environments/dev/red-y-base.backend.hcl
terraform -chdir=terraform/red-y-base plan -var-file=../environments/dev/red-y-base.tfvars -out=dev.tfplan
# Tras revisar recursos y costo:
terraform -chdir=terraform/red-y-base apply dev.tfplan

terraform -chdir=terraform/supabase-propio init -reconfigure -backend-config=../environments/dev/supabase-propio.backend.hcl
terraform -chdir=terraform/supabase-propio plan -var-file=../environments/dev/supabase-propio.tfvars -var-file=../environments/dev/state.auto.tfvars -out=dev.tfplan
```

`state.auto.tfvars` se pasa explicitamente porque vive fuera del directorio del modulo.
Los `.backend.hcl` son generados desde los outputs nuevos; no contienen credenciales.
El backend verifica el proyecto autenticado y el propietario del bucket.
Los proveedores verifican el proyecto permitido; servicios verifica tambien el entorno
y proyecto publicados por el estado de red. No usar workspaces: dejar `default`.

Para cambiar de entorno usar el script con ese nombre, reinicializar ambos backends con
sus archivos y pasar sus tfvars correspondientes. No usar planes guardados de otro entorno.
Las configuraciones preprod/prod son objetivos de prueba, no capacidad productiva validada.

## Limites actuales

- Dev comienza Single-AZ, una tarea por servicio y sin escalado adicional ni dashboard.
- Multi-AZ y clase RDS deben comprobarse contra disponibilidad y plan del proyecto.
- ECS necesita imagenes subidas a ECR y preparacion de roles/esquema SQL antes de estar sano.
- Acceso diario, Budgets/SNS y rotacion automatica siguen pendientes de la siguiente etapa.
- No desplegar los tres entornos juntos con el presupuesto total de USD 120.

## Cierre de una sesion

Con el backend y tfvars del mismo entorno: revisar primero un plan `-destroy` de servicios,
aplicarlo y despues revisar/aplicar el de red/base. Conservar bootstrap y sus estados.
No vaciar buckets/repositorios ni eliminar snapshots indiscriminadamente: revisar inventario
y datos ficticios/evidencia que se quieran conservar. Verificar endpoints, ALB, tareas, RDS,
ENI, IP publicas, ECR, S3, logs y secretos en recuperacion tras el desmontaje.
La verificacion automatizada del inventario residual es un pendiente, no una garantia actual.
