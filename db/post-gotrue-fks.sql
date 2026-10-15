-- Estas 4 relaciones quedaron fuera de schema.sql a proposito: necesitan que
-- auth.users ya exista, y esa tabla la crea GoTrue solo, al arrancar
-- (Fase 2 -- ver docs/PLAN.md). Correr esto DESPUES de que GoTrue este
-- desplegado y haya corrido sus migraciones.

alter table profiles          add constraint profiles_id_fkey           foreign key (id)      references auth.users(id) on delete cascade;
alter table students          add constraint students_user_fkey         foreign key (user_id) references auth.users(id);
alter table noticias_leidas   add constraint noticias_leidas_user_fkey  foreign key (user_id) references auth.users(id) on delete cascade;
alter table contenidos_vistos add constraint contenidos_vistos_user_fkey foreign key (user_id) references auth.users(id) on delete cascade;
