-- Indices de rendimiento -- NINGUNO de estos existia en el esquema cargado
-- (db/schema.sql no define ni uno solo).
--
-- Hallazgo 2026-10-17, probando el dashboard real contra la base: con
-- 30.000 alumnos, cada politica de seguridad (RLS) compara `academia_id`
-- contra `mi_academia()` en CADA FILA de la tabla -- sin un indice en esa
-- columna, Postgres tiene que recorrer la tabla entera para resolver eso,
-- en cada consulta. Confirmado como la causa (junto con la falta de CPU de
-- `db.t4g.micro`, ver CLAUDE.md) de los `504 Gateway Timeout` /
-- `PGRST003: Timed out acquiring connection from pool` que tiraba
-- PostgREST al cargar el dashboard.
--
-- Un indice no cuesta CPU extra en AWS (es espacio en disco, centavos) y
-- es la forma correcta de resolver esto -- mas barato y mas efectivo que
-- subir el tamano de la instancia (que ademas esta planta no permite, ver
-- variables.tf: FreeTierRestrictionError).
--
-- Separado de db/schema.sql a proposito: ese archivo es la foto exportada
-- de la Supabase real (si a produccion tampoco le pusieron estos indices,
-- es un hallazgo aparte, para Bryan, no algo que este repo deba "arreglar"
-- silenciosamente ahi). `create index if not exists` en todos: correr este
-- archivo de nuevo no rompe nada.

-- =========================================================================
-- academia_id -- la columna que revisa CADA politica de seguridad (RLS),
-- via mi_academia(). El indice mas importante de todos, por lejos.
-- =========================================================================
create index if not exists idx_sedes_academia          on sedes (academia_id);
create index if not exists idx_cycles_academia          on cycles (academia_id);
create index if not exists idx_personal_academia        on personal (academia_id);
create index if not exists idx_salones_academia         on salones (academia_id);
create index if not exists idx_profiles_academia        on profiles (academia_id);
create index if not exists idx_students_academia        on students (academia_id);
create index if not exists idx_matriculas_academia      on matriculas (academia_id);
create index if not exists idx_cuotas_academia          on cuotas (academia_id);
create index if not exists idx_pagos_academia           on pagos (academia_id);
create index if not exists idx_horarios_academia        on horarios (academia_id);
create index if not exists idx_asistencias_academia     on asistencias (academia_id);
create index if not exists idx_admin_sedes_academia     on admin_sedes (academia_id);
create index if not exists idx_universidades_academia   on universidades (academia_id);
create index if not exists idx_carreras_academia        on carreras (academia_id);
create index if not exists idx_metas_alumno_academia    on metas_alumno (academia_id);
create index if not exists idx_observaciones_academia   on observaciones_tutor (academia_id);
create index if not exists idx_noticias_academia        on noticias (academia_id);
create index if not exists idx_contenidos_academia      on contenidos (academia_id);
create index if not exists idx_exams_academia           on exams (academia_id);
create index if not exists idx_exam_results_academia    on exam_results (academia_id);
create index if not exists idx_answer_keys_academia     on answer_keys (academia_id);

-- =========================================================================
-- Las funciones de auth (mi_puesto(), mis_salones(), etc.) buscan por
-- user_id en cada pedido -- sin indice, cada login/consulta recorre toda
-- la tabla de alumnos o de personal para encontrar la fila del usuario.
-- =========================================================================
create index if not exists idx_students_user          on students (user_id);
create index if not exists idx_personal_user          on personal (user_id);

-- =========================================================================
-- Llaves foraneas que se usan en JOINs o en lookups frecuentes. Postgres
-- NO crea un indice automatico para una FK (solo para la primary key del
-- lado "uno" de la relacion) -- hay que crearlo a mano en el lado "muchos".
-- =========================================================================
create index if not exists idx_students_salon          on students (salon_id);
create index if not exists idx_salones_cycle            on salones (cycle_id);
create index if not exists idx_salones_tutor            on salones (tutor_id);
create index if not exists idx_matriculas_student       on matriculas (student_id);
create index if not exists idx_matriculas_cycle         on matriculas (cycle_id);
create index if not exists idx_matriculas_salon         on matriculas (salon_id);
create index if not exists idx_cuotas_student           on cuotas (student_id);
create index if not exists idx_pagos_alumno             on pagos (alumno_id);
create index if not exists idx_horarios_salon           on horarios (salon_id);
create index if not exists idx_horarios_profesor        on horarios (profesor_id);
create index if not exists idx_asistencias_student      on asistencias (student_id);
create index if not exists idx_carreras_universidad     on carreras (universidad_id);
create index if not exists idx_metas_alumno_student     on metas_alumno (student_id);
create index if not exists idx_metas_alumno_carrera     on metas_alumno (carrera_id);
create index if not exists idx_metas_alumno_tutor       on metas_alumno (tutor_id);
create index if not exists idx_observaciones_student    on observaciones_tutor (student_id);
create index if not exists idx_observaciones_tutor_id   on observaciones_tutor (tutor_id);
create index if not exists idx_contenidos_cycle         on contenidos (cycle_id);
create index if not exists idx_contenidos_salon         on contenidos (salon_id);
create index if not exists idx_exam_results_exam        on exam_results (exam_id);
create index if not exists idx_exam_results_student     on exam_results (student_id);
create index if not exists idx_answer_keys_exam         on answer_keys (exam_id);

-- Despues de crear indices nuevos sobre tablas con muchas filas, conviene
-- refrescar las estadisticas del planificador de consultas -- si no, puede
-- tardar en "darse cuenta" de que el indice nuevo existe y conviene usarlo.
analyze;
