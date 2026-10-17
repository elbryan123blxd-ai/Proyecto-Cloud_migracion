-- GoTrue no sabe leer NULL en varias columnas de texto de auth.users
-- (confirmation_token, email_change, y la familia completa de "tokens" y
-- "pendientes de cambio") -- se cae con "Scan error ... converting NULL
-- to string is unsupported" apenas intenta leer cualquier fila que las
-- tenga en NULL. GoTrue las deja en '' (string vacio) cuando CREA un
-- usuario por su propia API; un INSERT a mano que no las menciona las
-- deja en NULL si la columna no tiene default.
--
-- En vez de enumerar las columnas una por una (encontramos
-- confirmation_token primero, despues email_change -- iban a seguir
-- apareciendo de a una), este bloque recorre TODAS las columnas de texto
-- de auth.users y las arregla de una sola pasada. Idempotente: correrlo
-- de nuevo no rompe nada, las que ya estan en '' no se tocan (el WHERE
-- filtra por IS NULL).
--
-- Excluye las columnas con restriccion UNIQUE (como "phone"): ponerlas
-- todas en '' choca -- dos filas no pueden tener el mismo valor en una
-- columna unica, y el primer intento de este script reviento justo ahi
-- ("duplicate key value violates unique constraint users_phone_key"),
-- deshaciendo TODO el bloque de un viaje (es una sola transaccion). Esas
-- columnas unicas (phone, el "login alternativo" de Supabase) no las
-- necesita el login por email/password -- se dejan en NULL, que es su
-- estado normal cuando nadie uso ese login alternativo nunca.
do $$
declare
  col text;
begin
  for col in
    select c.column_name
    from information_schema.columns c
    where c.table_schema = 'auth'
      and c.table_name = 'users'
      and c.data_type in ('text', 'character varying')
      and c.column_name not in (
        select kcu.column_name
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on tc.constraint_name = kcu.constraint_name
         and tc.table_schema = kcu.table_schema
        where tc.table_schema = 'auth'
          and tc.table_name = 'users'
          and tc.constraint_type in ('UNIQUE', 'PRIMARY KEY')
      )
  loop
    execute format('update auth.users set %I = '''' where %I is null', col, col);
  end loop;
end $$;
