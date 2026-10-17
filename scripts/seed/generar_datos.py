"""
Generador de datos falsos para el clon de Academia Premier.

Rellena las 25 tablas de db/schema.sql respetando FKs, con un volumen que
coincide con la "Capacidad objetivo" documentada en CLAUDE.md: ~60
administradores/directores/tutores y ~30.000 alumnos, repartidos entre
varias academias (para que el multi-tenant y las politicas RLS tengan
algo real que aislar).

NINGUN dato real entra aca -- todo lo genera Faker. Pensado para correr
UNA VEZ contra Aurora Serverless v2, despues de que exista (Fase 1 del
plan) y de que GoTrue haya corrido sus propias migraciones (Fase 2) --
el insert a auth.users de abajo usa las columnas estandar de GoTrue, pero
hay que confirmarlas contra el schema real una vez GoTrue este desplegado.

Uso:
    pip install -r requirements.txt
    export DATABASE_URL="postgresql://usuario:pass@host:5432/postgres"
    python generar_datos.py --academias 5 --alumnos 30000 --admins 60

Password de prueba para TODOS los usuarios generados: "Demo1234!"
(documentado aca y en nada mas -- no es un secreto real).
"""

import argparse
import os
import random
import sys
import uuid
from datetime import date, timedelta

import bcrypt
import psycopg2
from faker import Faker
from psycopg2.extras import execute_values

fake = Faker("es_ES")
PASSWORD_DEMO = "Demo1234!"
PASSWORD_HASH = bcrypt.hashpw(PASSWORD_DEMO.encode(), bcrypt.gensalt()).decode()

ROLES_PERSONAL_DOCENTE = "Docente"
ROLES_PROFILE_DIRECTOR = "director"
ROLES_PROFILE_ADMIN_SEDE = "admin_sede"


def conectar():
    url = os.environ.get("DATABASE_URL")
    if not url:
        sys.exit("Falta DATABASE_URL. Ej: export DATABASE_URL='postgresql://user:pass@host:5432/postgres'")
    return psycopg2.connect(url)


def crear_auth_user(cur, nombre_completo, email):
    """Inserta en auth.users (schema que crea GoTrue). Columnas estandar de
    GoTrue/Supabase Auth, confirmadas contra el schema real en Fase 2.

    Las columnas de "tokens" (confirmation_token, recovery_token, etc.) se
    mandan como '' a proposito -- GoTrue las deja asi cuando crea un
    usuario por su propia API, nunca en NULL. Si quedan en NULL (el default
    de la columna, al no mencionarlas en el insert), GoTrue se cae al
    LOGUEAR a ese usuario con "Scan error ... converting NULL to string is
    unsupported" -- encontrado en Fase 3, 2026-10-17, con los 30.100
    usuarios del primer seed. Fix de los que ya existen:
    db/fix-auth-users-tokens-null.sql."""
    user_id = str(uuid.uuid4())
    cur.execute(
        """
        insert into auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, created_at, updated_at,
            raw_app_meta_data, raw_user_meta_data,
            confirmation_token, recovery_token,
            email_change_token_new, email_change_token_current,
            phone_change_token, reauthentication_token
        ) values (
            '00000000-0000-0000-0000-000000000000', %s, 'authenticated', 'authenticated',
            %s, %s, now(), now(), now(), '{"provider":"email","providers":["email"]}',
            %s,
            '', '', '', '', '', ''
        )
        """,
        (user_id, email, PASSWORD_HASH, psycopg2.extras.Json({"nombre": nombre_completo})),
    )
    return user_id


def generar_academias(cur, n):
    academias = []
    for _ in range(n):
        academia_id = str(uuid.uuid4())
        nombre = f"Academia {fake.city()}"
        cur.execute(
            """insert into academias (id, nombre, ruc, ciudad, telefono, contacto)
               values (%s, %s, %s, %s, %s, %s)""",
            (academia_id, nombre, fake.numerify("20#########"), fake.city(),
             fake.numerify("9########"), fake.name()),
        )
        academias.append(academia_id)
    return academias


def generar_sedes(cur, academia_id, n=3):
    sedes = []
    for _ in range(n):
        sede_id_int = cur.execute(
            """insert into sedes (nombre, zona, direccion, academia_id, aforo_maximo, ciclos)
               values (%s, %s, %s, %s, %s, %s) returning id, nombre""",
            (f"Sede {fake.street_name()}", random.choice(["Norte", "Sur", "Centro", "Este"]),
             fake.address(), academia_id, random.randint(300, 1200), ["2026-I", "2026-II"]),
        )
        row = cur.fetchone()
        sedes.append(row[1])  # guardamos el nombre, que es lo que usan las FKs de texto (sede)
    return sedes


def generar_cycles(cur, academia_id, n=3):
    cycles = []
    for i in range(n):
        cycle_id = f"{academia_id[:8]}-C{i}"
        cur.execute(
            """insert into cycles (id, nombre, precio, duracion, categoria, tipo, tipo_clase,
                                    academia_id, precio_num)
               values (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (cycle_id, f"Ciclo {['Verano','Anual','Semestral'][i % 3]}", "S/ 800", "4 meses",
             "Preuniversitario", "Regular", "Presencial", academia_id, 800.0),
        )
        cycles.append(cycle_id)
    return cycles


def generar_personal(cur, academia_id, sedes, n_docentes, n_tutores, n_directores, n_admin_sede):
    """Devuelve dict con listas de ids de personal por rol, y mapea cada uno
    a su auth.users (profiles solo se crea para director/admin_sede/tutor que
    tienen login propio; docentes del schema tambien loguean via mi_personal())."""
    personal = {"docentes": [], "tutores": [], "directores": [], "admin_sede": []}

    def crear(rol_personal, cargo, es_director=False, es_admin_sede=False):
        nombre = fake.name()
        email = fake.unique.email()
        sede = random.choice(sedes)
        personal_id = f"P-{uuid.uuid4().hex[:8]}"
        cur.execute(
            """insert into personal (id, nombre, rol, cargo, sede, telefono, email,
                                      contrato, academia_id, sueldo)
               values (%s, %s, %s, %s, %s, %s, %s, 'Planilla', %s, %s)""",
            (personal_id, nombre, rol_personal, cargo, sede, fake.numerify("9########"),
             email, academia_id, random.randint(1500, 4500)),
        )
        user_id = crear_auth_user(cur, nombre, email)
        cur.execute("update personal set user_id = %s where id = %s", (user_id, personal_id))

        if es_director or es_admin_sede:
            rol_profile = ROLES_PROFILE_DIRECTOR if es_director else ROLES_PROFILE_ADMIN_SEDE
            cur.execute(
                "insert into profiles (id, nombre, rol, academia_id) values (%s, %s, %s, %s)",
                (user_id, nombre, rol_profile, academia_id),
            )
            if es_admin_sede:
                cur.execute(
                    "insert into admin_sedes (profile_id, sede, academia_id) values (%s, %s, %s)",
                    (user_id, sede, academia_id),
                )
        return personal_id

    for _ in range(n_directores):
        personal["directores"].append(crear(ROLES_PERSONAL_DOCENTE, "Director", es_director=True))
    for _ in range(n_admin_sede):
        personal["admin_sede"].append(crear("Administrativo", "Admin de sede", es_admin_sede=True))
    for _ in range(n_docentes):
        personal["docentes"].append(crear(ROLES_PERSONAL_DOCENTE, "Docente"))
    for _ in range(n_tutores):
        personal["tutores"].append(crear("Tutor", "Tutor académico"))

    return personal


def generar_salones(cur, academia_id, sedes, cycles, personal, n=6):
    salones = []
    for i in range(n):
        salon_id = f"S-{uuid.uuid4().hex[:8]}"
        tutor_id = random.choice(personal["tutores"]) if personal["tutores"] else None
        cur.execute(
            """insert into salones (id, nombre, ciclo, aforo, turno, tutor, ubicacion,
                                     sede, academia_id, cycle_id, tutor_id)
               values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (salon_id, f"Salón {chr(65 + i)}", random.choice(cycles), random.randint(25, 40),
             random.choice(["Mañana", "Tarde"]), "Por asignar", f"Aula {i+1}",
             random.choice(sedes), academia_id, random.choice(cycles), tutor_id),
        )
        salones.append(salon_id)
    return salones


def generar_cursos(cur, academia_id, n=6):
    cursos = []
    nombres = ["Matemática", "Lenguaje", "Física", "Química", "Biología", "Historia"]
    for nombre in nombres[:n]:
        cur.execute(
            "insert into cursos (academia_id, nombre, area) values (%s, %s, %s)",
            (academia_id, nombre, "Ciencias"),
        )
        cursos.append(nombre)
    return cursos


def generar_students(cur, academia_id, sedes, salones, n):
    students = []
    hoy = date.today()
    for _ in range(n):
        nombre = fake.name()
        email = fake.unique.email()
        student_id = f"AL-{uuid.uuid4().hex[:10]}"
        sede = random.choice(sedes)
        salon_id = random.choice(salones)
        cur.execute(
            """insert into students (id, nombre, codigo, dni, email, telefono, ciclo,
                                      sede, academia_id, salon_id, estado)
               values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'Activo')""",
            (student_id, nombre, f"COD{uuid.uuid4().hex[:6].upper()}", fake.numerify("########"),
             email, fake.numerify("9########"), "2026-I", sede, academia_id, salon_id),
        )
        user_id = crear_auth_user(cur, nombre, email)
        cur.execute("update students set user_id = %s where id = %s", (user_id, student_id))
        students.append({"id": student_id, "nombre": nombre, "sede": sede, "salon_id": salon_id})
    return students


def generar_matriculas_cuotas_pagos(cur, academia_id, students, cycles):
    """Simplificado a proposito: sin comprobantes SUNAT (fuera de alcance,
    ver CLAUDE.md). Una matricula + una cuota por alumno, pago en la mitad."""
    hoy = date.today()
    rows_matriculas = []
    for s in students:
        matricula_id = str(uuid.uuid4())
        cycle_id = random.choice(cycles)
        rows_matriculas.append((matricula_id, academia_id, s["id"], cycle_id, s["sede"], 800.0))
        s["matricula_id"] = matricula_id

    execute_values(
        cur,
        """insert into matriculas (id, academia_id, student_id, cycle_id, sede, precio_acordado)
           values %s""",
        rows_matriculas,
    )

    rows_cuotas = [
        (academia_id, s["id"], s["matricula_id"], hoy.replace(day=1), 200.0,
         hoy.replace(day=1) + timedelta(days=30))
        for s in students
    ]
    execute_values(
        cur,
        """insert into cuotas (academia_id, student_id, matricula_id, periodo, monto, vence)
           values %s""",
        rows_cuotas,
    )

    rows_pagos = []
    for s in students[: len(students) // 2]:  # la mitad ya pagó, para que haya variedad
        rows_pagos.append((
            f"PG-{uuid.uuid4().hex[:8]}", s["id"], s["nombre"], "Pensión", hoy, "Pagado",
            s["sede"], hoy.replace(day=1), academia_id, "pension", 200.0,
            random.choice(["Yape", "Transferencia", "Efectivo"]),
        ))
    execute_values(
        cur,
        """insert into pagos (id, alumno_id, alumno_nombre, concepto, fecha, estado, sede,
                               periodo, academia_id, tipo, monto, metodo)
           values %s""",
        rows_pagos,
    )


def generar_horarios(cur, academia_id, salones, cursos, personal):
    rows = []
    for salon_id in salones:
        for dia in range(1, 6):  # lunes a viernes
            profesor_id = random.choice(personal["docentes"]) if personal["docentes"] else None
            rows.append((
                academia_id, salon_id, dia, "08:00", "10:00",
                random.choice(cursos), "Aula", profesor_id,
            ))
    execute_values(
        cur,
        """insert into horarios (academia_id, salon_id, dia, hora_inicio, hora_fin, curso, aula, profesor_id)
           values %s""",
        rows,
    )


def generar_asistencias_hoy(cur, academia_id, students):
    """El pico que simula la Fase 5 (prueba de carga): asistencia de hoy
    para todos los alumnos de la academia, igual que el escaneo de QR real."""
    hoy = date.today()
    rows = [
        (academia_id, s["id"], s["sede"], hoy, random.choice(["Presente", "Presente", "Presente", "Tardanza"]),
         "QR")
        for s in students
    ]
    execute_values(
        cur,
        """insert into asistencias (academia_id, student_id, sede, fecha, estado, metodo)
           values %s""",
        rows,
    )


def generar_universidades_carreras(cur, academia_id, n_u=3, n_c_por_u=4):
    universidades = []
    for _ in range(n_u):
        uid_ = str(uuid.uuid4())
        nombre = fake.company() + " University"
        cur.execute(
            "insert into universidades (id, academia_id, nombre, sigla) values (%s, %s, %s, %s)",
            (uid_, academia_id, nombre, nombre[:4].upper()),
        )
        universidades.append(uid_)
        for _ in range(n_c_por_u):
            cur.execute(
                """insert into carreras (academia_id, universidad_id, nombre, puntaje_objetivo)
                   values (%s, %s, %s, %s)""",
                (academia_id, uid_, fake.job(), random.randint(1200, 1900)),
            )
    return universidades


def generar_exams_resultados(cur, academia_id, cycles, students, n_exams=3):
    for i in range(n_exams):
        exam_id = f"EX-{academia_id[:6]}-{i}"
        cur.execute(
            """insert into exams (id, nombre, ciclo, fecha, puntaje_maximo, academia_id, numero)
               values (%s, %s, %s, %s, %s, %s, %s)""",
            (exam_id, f"Simulacro {i+1}", random.choice(cycles), date.today() - timedelta(days=30 * i),
             100, academia_id, i + 1),
        )
        rows = [
            (f"R-{uuid.uuid4().hex[:10]}", s["id"], exam_id, random.randint(30, 100), academia_id)
            for s in random.sample(students, min(len(students), 500))  # no todos rinden cada simulacro
        ]
        execute_values(
            cur,
            "insert into exam_results (id, student_id, exam_id, puntaje, academia_id) values %s",
            rows,
        )


def arreglar_tokens_null(cur):
    """Red de seguridad para el hallazgo de Fase 3 (2026-10-17): GoTrue no
    sabe leer NULL en varias columnas de texto de auth.users
    (confirmation_token, email_change, y toda esa familia de "tokens" y
    "pendientes de cambio") -- se cae con "Scan error ... converting NULL
    to string is unsupported" al loguear a cualquier usuario que las
    tenga en NULL. crear_auth_user() ya las manda en '' a proposito, pero
    esto corre igual, por si GoTrue suma una columna asi en una version
    futura que crear_auth_user todavia no conoce. Ver
    db/fix-auth-users-tokens-null.sql para el mismo arreglo corrido a
    mano, con el detalle completo en el comentario."""
    cur.execute(
        """
        do $$
        declare
          col text;
        begin
          for col in
            select column_name
            from information_schema.columns
            where table_schema = 'auth'
              and table_name = 'users'
              and data_type in ('text', 'character varying')
          loop
            execute format('update auth.users set %I = '''' where %I is null', col, col);
          end loop;
        end $$;
        """
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--academias", type=int, default=5)
    ap.add_argument("--alumnos", type=int, default=30000, help="total repartido entre todas las academias")
    ap.add_argument("--admins", type=int, default=60, help="total de directores+admin_sede+tutores repartido")
    ap.add_argument("--docentes-por-academia", type=int, default=8)
    args = ap.parse_args()

    alumnos_por_academia = args.alumnos // args.academias
    admins_por_academia = args.admins // args.academias
    directores = max(1, admins_por_academia // 6)
    admin_sede = max(1, admins_por_academia // 3)
    tutores = max(1, admins_por_academia - directores - admin_sede)

    conn = conectar()
    conn.autocommit = False
    cur = conn.cursor()

    try:
        print(f"Creando {args.academias} academias...")
        academias = generar_academias(cur, args.academias)

        for idx, academia_id in enumerate(academias, start=1):
            print(f"[{idx}/{len(academias)}] poblando academia {academia_id}...")
            sedes = generar_sedes(cur, academia_id)
            cycles = generar_cycles(cur, academia_id)
            personal = generar_personal(
                cur, academia_id, sedes,
                n_docentes=args.docentes_por_academia, n_tutores=tutores,
                n_directores=directores, n_admin_sede=admin_sede,
            )
            salones = generar_salones(cur, academia_id, sedes, cycles, personal)
            cursos = generar_cursos(cur, academia_id)
            students = generar_students(cur, academia_id, sedes, salones, alumnos_por_academia)
            generar_matriculas_cuotas_pagos(cur, academia_id, students, cycles)
            generar_horarios(cur, academia_id, salones, cursos, personal)
            generar_asistencias_hoy(cur, academia_id, students)
            generar_universidades_carreras(cur, academia_id)
            generar_exams_resultados(cur, academia_id, cycles, students)

            conn.commit()  # commit por academia, asi un fallo no tira todo el trabajo previo

        arreglar_tokens_null(cur)
        conn.commit()

        print("Listo. Password de prueba para todos los usuarios generados:", PASSWORD_DEMO)
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
