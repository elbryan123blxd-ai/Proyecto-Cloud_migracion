# Academia Premier · réplica de un SaaS sobre AWS

Infraestructura como código para reproducir los componentes principales de un SaaS
multi-tenant construido con Supabase y Next.js. **Es una réplica con datos generados,
preparada con criterios de producción; no es una migración de clientes reales.**

Producción permanece en Supabase/Vercel. Este entorno no se conecta a su base ni importa
datos reales. El frontend vive en otro repositorio y su despliegue completo sigue pendiente.

## Empieza aquí

Para una vista por entorno en VS Code, usa **Archivo → Abrir área de trabajo desde archivo**:

- [DEV](DEV.code-workspace) · barra verde.
- [PRE-PROD](PRE-PROD.code-workspace) · barra ámbar.
- [PRODUCCIÓN](PRODUCCION.code-workspace) · barra roja.

Cada vista incluye solo la configuración de su entorno y las carpetas compartidas necesarias.
Con **Ctrl+Shift+B** validas Terraform; en **Terminal → Ejecutar tarea** están las pruebas,
formato, preparación del backend y planes. [Detalles de las tareas](terraform/environments/README.md#espacios-de-trabajo-de-vs-code).

| Documento | Contenido |
|---|---|
| [Plan y estado](docs/PLAN.md) | Entregables, pendientes y criterios de aceptación |
| [Arquitectura](docs/ARQUITECTURA.md) | Topología, decisiones y límites actuales |
| [Seguridad y acceso](docs/SEGURIDAD.md) | Root, roles, RBAC/ABAC, RLS, GuardDuty y NACL |
| [Observabilidad](docs/OBSERVABILIDAD.md) | Dashboard, alarmas configurables y runbooks |
| [Operación](docs/OPERACION.md) | Despliegue, validación, recuperación y limpieza |
| [Costos](docs/COSTOS.md) | Método de estimación y costos todavía no verificados |
| [Guion de YouTube](docs/GUION-YOUTUBE.md) | Historia, demostraciones y evidencias |

## Arquitectura

```text
Usuarios / apps Next.js (hosting pendiente)
                │ HTTPS
     CloudFront + Functions (rutas y CORS)
                │ HTTP actualmente; TLS al origen pendiente
     ALB público · listeners 80 / 8081
                │
     VPC 10.0.0.0/16 · dos zonas de disponibilidad
       ├─ Subredes públicas: ALB
        ├─ Privadas aplicación: GoTrue :9999 / PostgREST :3000
        │                          │ PostgreSQL :5432
        └─ Privadas datos: RDS PostgreSQL (Single-AZ en dev)

     Endpoints privados: ECR, Secrets Manager, Logs; gateway S3
     CloudWatch: logs + dashboard; alarmas opt-in
     Objetivo pendiente: GuardDuty → EventBridge → SNS; CloudTrail; WAF
```

**[Diagrama de arquitectura objetivo](docs/arquitectura-objetivo.png).**
Muestra el **objetivo acordado el 23 NOV 2026**: dos subredes públicas,
cuatro privadas separadas por aplicación/datos, configuración Multi-AZ y notificaciones
internas mediante consultas mientras la app está en uso.
Incluye los endpoints Interface y el gateway S3 asociado a las rutas de aplicación.
La red de seis subredes, endpoints y separación por entorno ya está codificada;
rotación, permisos específicos y otros controles del objetivo siguen pendientes. El diagrama
no representa un inventario verificado de recursos activos en AWS.

## Estado y evidencia

**23 NOV 2026:** inventario inicial de Ohio en el proyecto `519119252721`: solo VPC y
subredes predeterminadas en las consultas de red; sin RDS, ALB, ECS, endpoints, NAT,
instancias EC2, EBS, EIP, ECR o secretos. S3 y DynamoDB sin recursos devueltos;
CloudFront sin distribuciones devueltas. No es un inventario de todos los servicios/regiones.
No se creó infraestructura durante esta revisión. Configuración y comandos por entorno:
[terraform/environments](terraform/environments/README.md).

La bitácora registra un despliegue y login de prueba en octubre de 2026, con 5 academias
y 30.000 alumnos generados. **No se ha vuelto a verificar esa cuenta en esta revisión.**
Que el login funcione no demuestra capacidad, alta disponibilidad ni aislamiento completo.

En el código hay tres módulos raíz de Terraform:

| Módulo | Recursos principales |
|---|---|
| `terraform/bootstrap` | Backend S3 y bloqueo DynamoDB |
| `terraform/red-y-base` | VPC, subredes, SG, endpoints, RDS y secreto de base |
| `terraform/supabase-propio` | ECR, ECS Fargate, ALB, CloudFront, S3, secretos, escalado y observabilidad |

La revisión añade restricciones de puertos en SG y un dashboard de métricas nativas.
Las alarmas se crean solo si se configuran umbrales y ventanas explícitos.
Estos cambios requieren `plan` y despliegue para existir en AWS.

## Decisiones principales

- **GoTrue + PostgREST:** conservar compatibilidad con el cliente Supabase y la autorización
  RLS. Cognito es una alternativa que exigiría diseñar la integración de claims, no abandonar RLS.
- **ECS Fargate:** encaja con servidores HTTP persistentes y sus pools de conexiones.
  No se ha demostrado que Lambda tenga un costo equivalente ni que sea incapaz de soportar la carga.
- **RDS PostgreSQL:** base privada administrada. Clase, capacidad y conveniencia frente a Aurora
  se deciden con mediciones y restricciones reales de la cuenta.
- **Sin NAT:** conectividad limitada a endpoints. Debe revisarse si se incorporan SMTP,
  proveedores OAuth u otras dependencias externas.
- **NACL predeterminada:** se conserva. El filtrado específico se realiza con SG; reglas NACL
  personalizadas quedan pospuestas.
- **RBAC primero:** roles AWS por responsabilidad y roles de negocio en PostgreSQL. ABAC
  selectivo es una evolución pendiente, no una capacidad ya implementada por tener etiquetas.

## Arranque

Consulta [OPERACION.md](docs/OPERACION.md) antes de aplicar: los backends y la región están
fijados a la cuenta original y existen pasos SQL e imágenes que Terraform no automatiza.

```powershell
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap validate
terraform -chdir=terraform/bootstrap plan
```

Después se trabaja en `red-y-base` y finalmente en `supabase-propio`. El nuevo dashboard
necesita el output `db_instance_id` del estado actualizado de `red-y-base`.

## Límites antes de llamarlo listo para producción

Acceso directo al ALB y HTTP al origen; CORS y redirects amplios; GoTrue con autoconfirmación;
imagen `latest`; GoTrue usando credenciales master de base; RDS Single-AZ; una tarea mínima
por servicio; restauración y carga sin evidencia actual. GuardDuty, CloudTrail, WAF,
OIDC de CI/CD y trazas todavía no están implementados en Terraform.

Los rangos de costo históricos **no son un presupuesto actualizado**. Ver [COSTOS.md](docs/COSTOS.md).

## Historial

[CLAUDE.md](CLAUDE.md) y [COMO-FUNCIONA.md](docs/COMO-FUNCIONA.md) conservan la bitácora
y el tutorial original. Para el estado y las decisiones actuales prevalecen los documentos
enlazados arriba. No se modifican nombres de recursos históricos `aurora_*` porque cambiarlos
sin migrar el estado puede provocar reemplazos innecesarios.
