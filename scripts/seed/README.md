# Generador de datos falsos

Rellena las 25 tablas de `db/schema.sql` con datos generados por Faker,
respetando las FKs. Ningún dato real entra acá.

## Uso

```
pip install -r requirements.txt
export DATABASE_URL="postgresql://usuario:pass@host:5432/postgres"
python generar_datos.py --academias 5 --alumnos 30000 --admins 60
```

Password de prueba para **todos** los usuarios generados: `Demo1234!`
(no es un secreto real, es solo para loguearse en la demo).

## Qué genera

| Tabla | Volumen (default) |
|---|---|
| academias | 5 |
| students (alumnos) | 30.000 repartidos entre las 5 |
| personal (docentes/tutores/directores/admin_sede) | ~60 repartidos |
| asistencias | una fila por alumno, fecha de hoy, `metodo='QR'` -- simula el pico de las 7:45am |
| matrículas, cuotas, pagos, horarios, exámenes, universidades, carreras | proporcionales |

## Cuándo correrlo

Requiere que Aurora ya exista (Fase 1) y que GoTrue haya corrido sus
migraciones en `auth` (Fase 2) -- el script inserta directo en
`auth.users` con las columnas estándar de GoTrue, pero conviene
confirmarlas contra el schema real una vez GoTrue esté desplegado.

No es parte del alcance de Fase 0 ejecutarlo contra una base real
(Aurora todavía no existe) -- acá solo queda el generador listo.
