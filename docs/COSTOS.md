# Costos: supuestos antes que cifras

Los rangos históricos de USD 48–60 y USD 120–170 mensuales no se consideran cotizaciones
actuales. No fueron recalculados para los controles nuevos ni contrastados en esta revisión
con consumo facturado. Créditos, saldo y vencimiento deben consultarse en la cuenta definitiva.

## Modelo de estimación

| Servicio | Variables a incluir |
|---|---|
| Fargate | vCPU-h, GB-h, número/tiempo de tareas y arquitectura de imagen |
| ALB | Horas + LCU según conexiones, bytes y reglas |
| RDS | Clase, horas, almacenamiento, I/O si aplica, backups/snapshots y excedentes CPU |
| Endpoints Interface | **4 servicios × 2 AZ = 8 ubicaciones endpoint-AZ por hora**, más datos |
| S3 gateway | Sin cargo del gateway; S3 sigue cobrando almacenamiento/requests/transferencia aplicables |
| CloudFront/Functions | Requests, transferencia y ejecuciones; verificar plan y beneficios vigentes |
| CloudWatch | Logs ingeridos/retenidos, consultas, dashboard, alarmas y métricas adicionales |
| GuardDuty | Fuentes/volumen analizados; Runtime Monitoring tiene costos adicionales |
| WAF | Web ACL, reglas, requests y funciones adicionales que se elijan |
| CloudTrail | Eventos/copia/almacenamiento según configuración; distinguir management/data events |
| Otros | Secrets Manager, KMS, SNS, DNS, hosting Next.js y direcciones IPv4 públicas |

La comparación NAT vs endpoints debe incluir horas, AZ, tráfico, transferencia entre AZ
y requisitos de conectividad. Los endpoints privados no son universalmente más baratos.

## Tres presupuestos distintos

1. **Demo por horas:** tiempo encendido, prueba de carga y recursos residuales.
2. **Réplica 24/7:** mínimos de ECS, RDS, ALB y endpoints aunque no haya usuarios.
3. **Objetivo productivo hipotético:** redundancia, capacidad medida, retención y operación.

No aplicar descuentos por compromiso a un entorno efímero. Free Tier/créditos son beneficios
condicionados por cuenta y vigencia, no propiedades permanentes del diseño.

## Qué registrar para el video

- Fecha, región, moneda y horas de ejecución.
- Estimación por servicio con AWS Pricing Calculator y supuestos guardados.
- Consumo observado en Billing/Cost Explorer, teniendo en cuenta el retraso de datos.
- Costo puntual de la prueba de carga, separado del costo mensual proyectado.
- Alertas de presupuesto configuradas y recibidas. Un presupuesto no es un corte automático de gasto.

Fuentes: [Calculator](https://calculator.aws/), [PrivateLink](https://aws.amazon.com/privatelink/pricing/),
[CloudWatch](https://aws.amazon.com/cloudwatch/pricing/), [GuardDuty](https://aws.amazon.com/guardduty/pricing/).
