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
