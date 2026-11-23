# Observabilidad y respuesta operativa

## Qué incluye esta entrega

`terraform/supabase-propio/observabilidad.tf` añade un dashboard CloudWatch y un catálogo
de alarmas opt-in usando métricas nativas. No requiere Container Insights ni agente.
Los logs de GoTrue y PostgREST ya existían, con retención de siete días.

El dashboard se crea por defecto y puede generar cargos. Para desactivarlo:
`observabilidad_dashboard = false`. No se crean alarmas ni suscripciones SNS por defecto.

### Paneles

| Panel | Namespace/dimensiones | Interpretación |
|---|---|---|
| CPU y memoria por servicio | AWS/ECS, ClusterName + ServiceName | Promedio de tareas; puede ocultar una tarea saturada |
| Latencia p95 por target group | AWS/ApplicationELB, LoadBalancer + TargetGroup | Segundos del origen, no tiempo completo del navegador |
| Requests y 5xx | AWS/ApplicationELB, LoadBalancer | Conteos Sum por minuto, no porcentaje de error |
| Targets saludables | AWS/ApplicationELB, LoadBalancer + TargetGroup | Minimum; no sustituye un flujo de usuario |
| CPU, conexiones y espacio/memoria libres | AWS/RDS, DBInstanceIdentifier | Métricas de instancia; no de una academia |
| Créditos T4g | AWS/RDS, DBInstanceIdentifier | Balance, excedentes y cargos; revisar Unlimited |

Los créditos se visualizan en ventanas de cinco minutos. Las métricas pueden no aparecer
si no hay tráfico, la instancia no es burstable o el servicio no tiene tareas ejecutándose.
No confundir ausencia de datos con valor cero. El dashboard no publica ni comparte datos
públicamente; requiere acceso IAM a CloudWatch.

## Despliegue y dependencias

1. Aplicar primero `red-y-base`: publica el nuevo output `db_instance_id`.
2. Ejecutar plan de `supabase-propio`: debe leer ese output del estado remoto actualizado.
3. Revisar costo y cambios, aplicar y abrir `academia-premier-<entorno>-replica` en CloudWatch.
4. Generar tráfico sintético y confirmar las dimensiones/series de ambos servicios y RDS.

Sin el paso 1 el nuevo módulo de observabilidad no puede leer el identificador RDS.
No se consulta automáticamente la cuenta AWS durante la validación local.

Pruebas locales sin AWS: `terraform -chdir=terraform/supabase-propio test` (suite verificada
con Terraform 1.16.5). Usan proveedores mock y remote state sintético para comprobar renderizado del
dashboard, dimensiones de alarmas, desactivación y validación de ventanas.

## Alarmas: elegir umbrales con baseline

Claves disponibles: `gotrue_cpu`, `gotrue_memoria`, `postgrest_cpu`, `postgrest_memoria`,
`gotrue_unhealthy`, `postgrest_unhealthy`, `db_cpu`, `db_memoria`, `db_almacenamiento`.

- CPU/memoria ECS y CPU RDS: Average, dispara por encima del umbral.
- Targets no saludables: Maximum, dispara con valor mayor o igual al umbral.
- Memoria/almacenamiento libres RDS: Minimum, dispara por debajo del umbral, en bytes.
- Todos usan `treat_missing_data = "missing"`: sin datos puede aparecer INSUFFICIENT_DATA.
  No hay notificación de ausencia de datos ni detector independiente de servicio caído todavía.

Ejemplo **ilustrativo** para una prueba controlada, no baseline de producción:

```hcl
observabilidad_alarmas = {
  gotrue_unhealthy = {
    threshold           = 1
    period              = 60
    evaluation_periods  = 3
    datapoints_to_alarm = 2
  }
  postgrest_unhealthy = {
    threshold           = 1
    period              = 60
    evaluation_periods  = 3
    datapoints_to_alarm = 2
  }
}
```

Para notificaciones, proporcionar `observabilidad_sns_arn` con un topic existente en
`us-east-2`. Confirmar suscripción del destinatario y policy que permite a CloudWatch
publicar desde las alarmas autorizadas; si usa una CMK, revisar también permisos KMS.
Sin ARN las alarmas solo muestran estado. No se crea un destinatario ficticio.

La evaluación M-de-N reduce ruido. Alarmas notifican cambios de estado, no cada minuto
que permanecen en ALARM. Probar ALARM → OK y registrar hora/recepción.

## Evolución pendiente

1. **Baseline:** medir login, carga del dashboard y marcación de asistencia por separado.
2. **SLI/SLO:** acordar disponibilidad y latencia p95 por flujo, ventana y volumen mínimo.
   Una propuesta inicial se registra como objetivo, nunca como resultado alcanzado.
3. **Errores:** porcentaje 5xx con denominador correcto y mínimo de requests. Separar errores
   del balanceador de errores del backend; no dividir ciegamente métricas con poblaciones distintas.
4. **Disponibilidad:** prueba sintética externa de login + lectura permitida; detectar tareas
   ausentes y fallos de despliegue. UnHealthyHostCount no detecta todos los casos sin targets.
5. **Logs:** correlación y estructura donde los binarios lo permitan; evitar cuerpos, cookies,
   JWT y datos personales. Identificadores de usuario no deben ser etiquetas de métricas.
6. **Trazas:** OpenTelemetry en Next.js/servicios compatibles, propagación, muestreo y exportación
   probados. No afirmar una traza completa hasta verificar compatibilidad GoTrue/PostgREST.
   Una nueva salida de telemetría puede requerir endpoints adicionales en esta VPC sin NAT.
7. **Base:** consultas costosas, locks, transacciones e I/O; evaluar herramientas de diagnóstico
   RDS disponibles y su costo. No habilitar logging indiscriminado de todas las sentencias.
8. **Eventos:** fallos/rollbacks ECS y hallazgos GuardDuty hacia responsable; auditoría CloudTrail.

## Runbooks iniciales

### API lenta / 504 / PGRST003

1. Correlacionar horario de error con p95 del target group, 5xx, targets y logs PostgREST.
2. Revisar CPU/memoria de ECS, conexiones RDS, locks e I/O. Revisar pool y límite de conexiones.
3. Inspeccionar consultas representativas con `EXPLAIN (ANALYZE, BUFFERS)` usando datos de prueba.
4. Comparar antes/después de un cambio. Subir tareas aumenta pools: no escalar sin revisar DB.
5. Confirmar recuperación del flujo y latencia, no solo CPU más baja.

### Créditos de CPU RDS

`CPUCreditBalance = 0` no prueba throttling de T4g Unlimited. Correlacionar
`CPUSurplusCreditBalance`, `CPUSurplusCreditsCharged`, CPU, memoria, consultas, locks e I/O.
La bitácora original atribuyó una causa que todavía necesita revalidación.

### Target no saludable / tarea no arranca

1. Revisar health check y razón de parada/despliegue ECS.
2. Si falla pull ECR: endpoints ECR, DNS, rutas S3 y egress a prefix list S3.
3. Si falla acceso a secretos/logs: execution role, SG :443 y endpoint correspondiente.
4. Si falla DB: SG :5432, secreto, rol DB y migraciones. No copiar secretos en logs/chat.

### Hallazgo GuardDuty

Identificar tipo, recurso y período; priorizar secuencias correlacionadas; correlacionar con
CloudTrail y eventos de red disponibles. Conservar evidencia en destino privado y ejecutar
la respuesta autorizada para ese caso. Documentar resolución y tiempo de detección/respuesta.

## Evidencia mínima

Dashboard con tráfico; alarma ALARM/OK y entrega recibida; operación fallida identificada
en logs; tabla de baseline; prueba multi-tenant; prueba de restauración. Grabar el video
después de obtener esa evidencia y ocultar tokens, secretos y datos de acceso.
