# Plan y estado de la réplica

Actualizado: 2026-11-23. Alcance confirmado: **datos generados, criterios de producción,
sin migrar clientes ni conectarse a Supabase de producción**.

## Cómo interpretar el estado

- **Código:** el recurso o cambio existe en el repositorio.
- **Histórico:** la bitácora registra una ejecución; necesita revalidación en la cuenta definitiva.
- **Pendiente:** no hay implementación o evidencia suficiente.

Un `terraform validate` no prueba conectividad, capacidad ni que el recurso esté desplegado.

## 1. Fundaciones y arquitectura

Avance del 23 NOV: proyecto nuevo `519119252721`, Ohio; inventario inicial sin recursos de
la réplica en los servicios consultados. Codificadas seis subredes, RDS en datos, endpoints
en aplicación, nombres/etiquetas y estados por entorno, control del proyecto permitido y
rechazo de remote state de otro entorno. Pruebas locales con mocks; no desplegado.
Bootstrap y backends nuevos preparados en [terraform/environments](../terraform/environments/README.md).
Acceso diario y alertas de gasto se prepararán junto con los servicios, según lo acordado.

| Entregable | Estado | Criterio para cerrar |
|---|---|---|
| Bootstrap, red, base, GoTrue y PostgREST | Código + histórico | Plan revisado y endpoints saludables en cuenta definitiva |
| Seed de 5 academias / 30.000 alumnos | Código + histórico | Recuento e integridad comprobados sin datos reales |
| Cuenta definitiva, región y presupuesto | Pendiente de confirmar | Documentar restricciones vigentes y alertas recibidas |
| Diagrama y documentación actualizados | Código | Comparar con plan y recursos tras desplegar |

## 2. Seguridad y acceso

- [x] Acordar mantener NACL predeterminada, sin NACL personalizadas.
- [x] Restringir en código los puertos ALB → servicios y servicios → red privada.
- [ ] Aplicar y comprobar login, consultas y pull de imágenes tras el cambio de SG.
- [ ] Resolver acceso humano: root reservado, MFA y rol diario con sesiones temporales.
- [ ] Separar lectura, despliegue y administración; evaluar Identity Center en cuenta definitiva.
- [ ] Restringir origen ALB a la distribución autorizada y añadir TLS al origen.
- [ ] CORS/redirects con listas explícitas; desactivar registro público si el modelo no lo necesita.
- [ ] Roles de base específicos para GoTrue; revisar grants y uso de `service_role`.
- [ ] Roles de ejecución separados por servicio y trust policies acotadas.
- [ ] GuardDuty con circuito de notificación probado; Runtime Monitoring evaluado con costo.
- [ ] CloudTrail persistente con destino privado, cifrado y retención definida.
- [ ] WAF con reglas evaluadas y rate limiting que contemple academias detrás de una misma IP.
- [ ] Matriz RBAC/RLS positiva y negativa ejecutada entre dos academias.
- [ ] ABAC selectivo solo donde se confirme soporte y control de cambios de tags.

Ver [SEGURIDAD.md](SEGURIDAD.md).

## 3. Observabilidad y recuperación

- [x] Dashboard en código con ECS, ALB y RDS.
- [x] Catálogo de alarmas opt-in, sin inventar umbrales de capacidad.
- [ ] Actualizar output de base y desplegar dashboard.
- [ ] Medir baseline, elegir umbrales/ventanas y confirmar entrega SNS.
- [ ] Alertar errores/latencia y ausencia de servicio con métricas apropiadas.
- [ ] Registrar eventos de despliegue/fallos ECS y consulta sintética de usuario.
- [ ] Trazas en componentes compatibles; comprobar propagación y muestreo.
- [ ] Restaurar backup en una base aislada y medir RTO/RPO observados.

Ver [OBSERVABILIDAD.md](OBSERVABILIDAD.md) y [OPERACION.md](OPERACION.md).

## 4. Apps, automatización y carga

- [ ] Inventariar qué apps y APIs necesitan Storage, Realtime, funciones y correo.
- [ ] Elegir hosting Next.js según SSR/ISR/middleware y registrar versiones soportadas.
- [ ] Conectar solo a la réplica y probar los flujos incluidos en el alcance.
- [ ] CI/CD con OIDC, rol acotado, `fmt`, `validate`, lint y escaneo de IaC.
- [ ] Fijar imágenes por versión/digest y probar rollback.
- [ ] Automatizar orden de migraciones SQL y carga de imágenes.
- [ ] Prueba de carga: 60 operadores y alumnos en oleadas, con ventanas y requests por flujo definidos.
- [ ] Medir latencia p95/p99, errores, conexiones, CPU y límite de escalado. Guardar resultados.

30.000 alumnos registrados no equivalen a 30.000 solicitudes simultáneas. La carga se define
por operaciones, frecuencia, duración de ventanas y concurrencia, no solo por filas de la base.

## 5. Presentación y cierre

- [x] Guion técnico con segmentos condicionados a evidencia real.
- [ ] Actualizar diagrama con recursos y controles efectivamente desplegados.
- [ ] Registrar costos medidos y supuestos de estimación.
- [ ] Grabar demo, aislamiento, incidente controlado y recuperación.
- [ ] Destruir entorno de práctica y comprobar recursos residuales y cargos.

No hay una migración de producción, corte de tráfico real ni copia de datos de clientes.
