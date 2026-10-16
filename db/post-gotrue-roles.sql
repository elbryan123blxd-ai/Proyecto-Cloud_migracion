-- Roles de Postgres que Supabase Cloud crea solo al armar un proyecto nuevo.
-- Aca no existe ese paso automatico -- hay que crearlos a mano, UNA SOLA VEZ,
-- despues de que Fase 2 (terraform/supabase-propio/) este aplicada y ANTES
-- de que PostgREST intente conectarse (si no, falla con "role authenticator
-- does not exist").
--
-- Reemplazar REEMPLAZAR_CON_LA_PASSWORD por el valor real, obtenido con:
--   aws secretsmanager get-secret-value \
--     --secret-id academia-premier/postgrest/authenticator \
--     --query SecretString --output text | jq -r .password
-- (mismo patron que se uso para la password de Aurora al cargar db/schema.sql
-- -- nunca copiar la password del chat, siempre pedirla fresca a Secrets
-- Manager)

-- --- Los 3 roles que PostgREST usa para decidir que puede ver cada pedido ---
-- "nologin": nadie se conecta DIRECTO con estos roles, solo se activan via
-- "SET ROLE" despues de que PostgREST valida el JWT de cada pedido.
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls; -- bypassrls: el unico rol que se salta las políticas RLS, como el service_role real de Supabase

-- --- El rol con el que PostgREST SI se conecta -------------------------------
create role authenticator noinherit login password 'REEMPLAZAR_CON_LA_PASSWORD';
grant anon to authenticator;
grant authenticated to authenticator;
grant service_role to authenticator;

-- --- Permisos sobre lo que carga db/schema.sql -------------------------------
-- Quien decide que fila puede leer/escribir cada quien son las 88 policies
-- RLS que ya estan cargadas -- esto solo abre la puerta a nivel de schema y
-- tabla, el filtro real de verdad lo hacen las policies.
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;

-- Las 21 funciones de permisos (mi_academia(), is_director(), etc.) llaman a
-- auth.uid() en su cuerpo -- sin este grant, cada policy fallaria en tiempo
-- de ejecucion con "permission denied for schema auth", aunque la funcion
-- exista.
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Para que las tablas/funciones/sequences que se creen DESPUES de este
-- script (si alguna vez hace falta) hereden el mismo permiso sin repetir
-- este bloque a mano.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
