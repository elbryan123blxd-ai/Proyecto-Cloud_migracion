# Seguridad e identidad

Alcance: réplica con datos generados. Los controles indicados como pendientes no están
desplegados por el hecho de aparecer en el diagrama.

## Matriz de controles

| Control | Estado del código | Evidencia pendiente |
|---|---|---|
| Servicios/base privados, sin IP pública de tareas | Existente | Revalidar ENI, rutas y conectividad |
| SG por puertos 3000, 9999, 5432 y 443 | Ajustado en esta revisión | Plan sin reemplazos y prueba de flujos |
| NACL predeterminada | Se conserva | Comprobar asociaciones; sin NACL personalizadas |
| ALB exclusivo para distribución autorizada | Pendiente | Petición directa rechazada |
| TLS CloudFront → origen | Pendiente | Certificado válido y `https-only` |
| IAM roles ECS y secretos por ARN | Existente, compartidos | Separar por servicio y revisar trusts/grants |
| RLS y roles de negocio | SQL existente | Pruebas positivas/negativas multi-tenant |
| GuardDuty + notificación | Diseño pendiente | Cobertura, hallazgo de prueba y entrega |
| WAF y auditoría CloudTrail persistente | Pendiente | Registros/notificaciones y validación |
| CI/CD OIDC, RBAC humano, ABAC selectivo | Pendiente | Roles efectivos y pruebas de denegación |

## Root, usuario y cuenta no son lo mismo

- Root pertenece a la cuenta AWS: MFA, sin access keys, reservado a tareas que lo requieren.
- Acceso habitual: Identity Center/federación con credenciales temporales si está disponible.
- Separar rol de lectura/diagnóstico, rol de despliegue y rol administrativo excepcional.
- El acceso histórico IAM user + MFA + STS es una alternativa condicionada por la cuenta.
  Una clave permanente que obtiene sesiones temporales sigue siendo una clave permanente.
- La cuenta de la réplica debe estar aislada de cualquier cuenta futura de producción.
  Confirmar la cuenta definitiva antes de adaptar los backends Terraform.

No se crean usuarios de clientes como usuarios IAM. Alumnos y personal se autentican en
GoTrue y reciben permisos de aplicación, no acceso al control plane de AWS.

## RBAC y ABAC

**AWS RBAC:** roles por función; políticas con acciones y recursos mínimos; `iam:PassRole`
limitado a roles concretos y servicios esperados. CI/CD usa OIDC, sin claves AWS guardadas
en GitHub. Distinguir permisos de plan de permisos de apply cuando el pipeline esté diseñado.

**AWS ABAC:** evolución selectiva usando las etiquetas existentes `project`, `managedby`
y una futura `environment`. Validar soporte por acción/servicio, tags obligatorios al crear,
y permisos para modificar etiquetas. Las etiquetas actuales NO aplican autorización solas.
No utilizar `academia_id` como principal tag para intentar resolver el RLS del SaaS.

**Aplicación:** RBAC por director/tutor/docente/alumno, junto con atributos de academia,
sede, salón y propiedad de registros, aplicados por grants y RLS en PostgreSQL.

### Pruebas de autorización requeridas

Usar dos academias sintéticas A/B y tokens de cada rol, sin `service_role` en las peticiones:

| Caso | Resultado esperado |
|---|---|
| Director A consulta datos permitidos A | Acceso conforme a la política |
| Director A consulta/modifica ID de B | Ninguna fila visible/modificable |
| Alumno A consulta perfil ajeno | Denegado según política |
| Tutor A consulta alumno fuera de su asignación | Denegado según política |
| JWT vencido o firma alterada | Sin acceso autenticado |
| Petición anónima a tabla privada | Sin acceso |
| UPDATE/INSERT con `academia_id` de B | Rechazo o ninguna modificación, nunca éxito cruzado |

Verificar también RPC, funciones `SECURITY DEFINER`, grants, `search_path` y políticas
`WITH CHECK`. Un listado vacío no basta: comprobar que la escritura no ocurrió.
`service_role` puede omitir RLS: solo backend controlado, nunca frontend ni grabaciones.

## GuardDuty y auditoría

GuardDuty detecta amenazas; no es un firewall ni sustituye WAF, IAM o RLS. El diseño
objetivo es **hallazgos → EventBridge → SNS → responsable con runbook**. Priorizar en
investigaciones las secuencias correlacionadas `AttackSequence:` cuando existan.

El alcance inicial considera detección fundamental. Runtime Monitoring de Fargate se
evalúa por separado: cobertura de tareas, agente, permisos, endpoints y costo propios.
No asumir que la detección fundamental observa procesos dentro de todos los contenedores.

GuardDuty analiza sus fuentes fundamentales sin exigir que publiquemos previamente nuestros
propios Flow Logs o trail. Para auditoría durable e investigación, el objetivo incluye
CloudTrail hacia S3 privado/cifrado con validación de logs y retención definida. El historial
de eventos de consola no sustituye una política de conservación.

Antes de dar el circuito por terminado: revisar cobertura regional, destino autorizado,
hallazgo de prueba, notificación recibida, permisos del operador y costo observado.
No se incluyen respuestas destructivas automáticas en este diseño inicial.

## Red, origen y WAF

Se mantienen NACL predeterminadas. SG es stateful; NACL es stateless. Añadir reglas NACL
sin necesidad concreta agrega mantenimiento y puede romper puertos efímeros.

El ALB sigue abierto en 80/8081: un WAF solo en CloudFront sería eludible por acceso directo.
La evolución debe combinar origen restringido y HTTPS, por ejemplo:

Preferir un VPC origin con ALB privado si la región, funciones requeridas y proveedor
Terraform elegido lo soportan; evaluar migración y posibles reemplazos antes de cambiarlo.
Si el ALB debe permanecer público, el siguiente es un diseño de transición:

1. Dominio de origen con certificado ACM regional válido en el ALB.
2. HTTPS al origen y reglas de listeners que solo acepten una cabecera secreta de la distribución.
3. SG limitado a la managed prefix list origin-facing de CloudFront, o evaluar VPC origins.
4. Probar rechazo de peticiones directas y de otra distribución.

La prefix list no identifica nuestra distribución. Además tiene un peso elevado en la
cuota de SG: no añadirla dos veces sin revisar límites. Una cabecera secreta sobre HTTP no
resuelve cifrado en tránsito y su valor quedaría en el estado Terraform.

WAF: evaluar reglas administradas y límites específicos para auth/API. Rate limiting por IP
debe contemplar que muchos alumnos pueden compartir la IP pública de una academia.

## Otros pendientes antes de endurecer la demo pública

- CORS explícito y redirects de GoTrue acotados; CORS no es autorización de API.
- Autoconfirmación y registro abierto solo para el flujo de demo decidido.
- GoTrue con rol DB propio; PostgREST mantiene `authenticator` con grants mínimos.
- Imágenes por versión/digest y escaneo de vulnerabilidades.
- Rotación de secretos coordinada: secretos inyectados por ECS se leen al arrancar;
  cambiar Secrets Manager no actualiza automáticamente tareas ya ejecutándose.
- Rotación JWT con estrategia de validación/transición; no cambiarlo sin coordinar servicios.
- Logs sin JWT, contraseñas ni contenido sensible; destinos y acceso limitados.

## Referencias

- [Buenas prácticas IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [ABAC](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html)
- [GuardDuty](https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html)
- [Runtime Monitoring ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-guard-duty.html)
