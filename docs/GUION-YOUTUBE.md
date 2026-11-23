# Guion YouTube · de Supabase a una réplica en AWS

Duración propuesta: 15–18 minutos. Título:
**«Repliqué mi SaaS de Supabase en AWS: Terraform, seguridad y observabilidad»**.

Este guion contiene segmentos pendientes de grabar. No presentarlos como implementados
hasta tener evidencia. No afirmar «migré producción» ni «soporta 30.000 concurrentes».

## 0:00–0:45 · Apertura

**Voz:** «Construí un SaaS para academias usando Supabase y Next.js. Quise entender qué
hay debajo: identidad, APIs, base de datos, red y operación. Así que preparé una réplica
en AWS con datos generados y Terraform. Hoy te muestro qué funciona, qué falló y qué
necesita para acercarse a criterios de producción».

**Pantalla:** demo breve de login y dashboard, si siguen funcionando. Rótulo permanente:
«Réplica · datos sintéticos». Si la demo no está desplegada, abrir con el diagrama y decirlo.

## 0:45–2:00 · El alcance

**Voz:** «Producción sigue en Supabase y Vercel. No moví datos de clientes. Generé academias,
usuarios y alumnos para comprobar la arquitectura. Tener 30.000 filas no significa tener
30.000 usuarios conectados al mismo tiempo».

**Pantalla:** repositorio de infraestructura, separación del frontend privado y lista
de funcionalidades incluidas/excluidas. Confirmar los recuentos antes de mostrarlos.

## 2:00–4:30 · Explicar el mapa

Abrir `arquitectura-objetivo.png` y seguir una petición:

1. HTTPS hacia CloudFront.
2. Selección por path y Function que retira el prefijo.
3. ALB en subredes públicas.
4. GoTrue/PostgREST en subredes privadas y conexión a PostgreSQL.
5. Endpoints ECR, S3, secretos y logs sin NAT.

**Voz:** «GoTrue y PostgREST reducen los cambios respecto del cliente Supabase. Mantengo
RLS para que la autorización viva también en la base. Usar Cognito requeriría adaptar
la integración, no obliga a eliminar RLS».

**Honestidad técnica:** señalar HTTP al origen, base Single-AZ y una tarea mínima si siguen
así. Dos AZ disponibles no significan alta disponibilidad de toda la aplicación.

## 4:30–6:30 · Seguridad por función

**Voz:** «Un Security Group decide qué se conecta. IAM decide quién puede operar AWS.
RLS decide qué filas puede tocar cada academia. WAF filtra HTTP y GuardDuty detecta
comportamientos sospechosos. Son controles complementarios».

**Pantalla:** puertos SG antes/después, matriz de permisos y página 2 del diagrama.
Etiquetar GuardDuty/WAF/CloudTrail como pendientes si no están desplegados.

Explicar root reservado con MFA y acceso habitual mediante rol temporal. NACL:
«Conservé la predeterminada; añadí reglas de SG precisas en lugar de complejidad sin necesidad».

**Demo pendiente:** usuario A intenta leer/escribir B. Mostrar resultado y comprobación DB,
sin JWT ni `service_role` visible. No usar un token privilegiado para demostrar RLS.

## 6:30–8:30 · Un fallo real: ECR y S3

**Voz:** «La imagen no descargaba. Parecía DNS o falta de Internet. ECR entrega las capas
desde S3: el gateway endpoint resolvía la ruta, pero el SG bloqueaba el destino».

**Pantalla:** error histórico anonimizado, ruta gateway S3 y egress a prefix list :443.
Si no se reproduce, decir «esto ocurrió durante el primer despliegue» y mostrar la bitácora.

## 8:30–11:00 · Observabilidad útil

**Voz:** «No basta con que el contenedor esté arriba. Quiero saber si el usuario puede
iniciar sesión, cuánto tarda una petición y dónde está el cuello de botella».

**Pantalla:** dashboard desplegado con CPU/memoria, p95, 5xx, targets y RDS.
Distinguir conteo de errores de tasa de errores y latencia del origen de latencia del usuario.

**Demo pendiente:** fallo controlado, alarma recibida, investigación y recuperación.
Medir tiempos reales. Si solo hay dashboard, describir las alarmas como siguiente paso.

**Voz:** «En la bitácora había atribuido una caída al saldo de créditos. Esa señal sola
no prueba throttling de una T4g Unlimited. Hay que correlacionar consultas, locks, I/O,
memoria y créditos excedentes. Los índices se justifican midiendo, y también tienen costo».

## 11:00–13:00 · Carga y recuperación

**Solo grabar tras ejecutar:** tráfico sintético escalonado, errores y percentiles, número
de tareas y conexiones DB. Informar duración, operaciones, tasa y límite del generador.

Si la prueba falla: mostrar el límite encontrado y el siguiente experimento. Si todavía
no se ejecutó: explicar el método sin animar gráficos como si fueran resultados.

**Restauración pendiente:** base aislada, dato recuperado y RTO/RPO observados.
«Un backup configurado no demuestra que puedo recuperar el sistema».

## 13:00–15:00 · Costos y automatización

**Pantalla:** desglose medido/calculado con fecha. Incluir ocho ubicaciones endpoint-AZ,
RDS/ALB mínimos, logs y servicios de seguridad. No repetir USD 48–60 como costo validado.

**Voz:** «No elegí servicios para llenar el diagrama. Cada uno debe justificar su operación
y su costo. El pipeline con OIDC y el resto de controles se muestran solo cuando estén probados».

## 15:00–16:00 · Cierre

**Voz:** «El resultado es una réplica reproducible con un camino claro de mejora. Lo valioso
es poder explicar decisiones, demostrar aislamiento y diagnosticar fallos. El repositorio
incluye Terraform, documentación y diagramas editables. Te dejo el enlace y los pendientes
para que puedas revisar qué está demostrado y qué sigue en construcción».

CTA: pregunta a la audiencia qué decisión cambiaría y por qué; enlace al repositorio.

## Material previo a grabar

- Commit y estado desplegado identificados.
- Diagramas actualizados; zoom legible y leyenda de implementado/objetivo.
- Demo funcional y aislamiento con cuentas generadas.
- Alarmas/notificaciones y recuperación probadas si se muestran.
- Costo con fecha y supuestos; evidencias de carga si se anuncian resultados.
- Ocultar tokens, secretos, headers de autorización y pantallas de credenciales.
