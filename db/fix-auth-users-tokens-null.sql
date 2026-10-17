-- GoTrue no sabe leer NULL en estas columnas de "tokens" de auth.users --
-- se cae con "Scan error ... converting NULL to string is unsupported"
-- apenas intenta leer cualquier fila que las tenga en NULL.
--
-- Pasa porque scripts/seed/generar_datos.py inserto los usuarios directo
-- por SQL (no por la API de GoTrue), y el INSERT no las menciono -- GoTrue
-- las deja en '' (string vacio) cuando CREA un usuario el mismo; un INSERT
-- a mano que no las toca las deja en NULL si la columna no tiene default.
--
-- Afecta a los ~30.100 usuarios del seed. Login roto para todos hasta
-- correr esto.

update auth.users set
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, ''),
  email_change_token_new = coalesce(email_change_token_new, ''),
  email_change_token_current = coalesce(email_change_token_current, ''),
  phone_change_token = coalesce(phone_change_token, ''),
  reauthentication_token = coalesce(reauthentication_token, '')
where confirmation_token is null
   or recovery_token is null
   or email_change_token_new is null
   or email_change_token_current is null
   or phone_change_token is null
   or reauthentication_token is null;
