-- Ejecutar una sola vez en Supabase SQL Editor.
-- No importa ni consulta datos históricos de Firebase.

create extension if not exists pgcrypto;

create table if not exists public.mallas (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  cliente text not null,
  punto text,
  ciudad text,
  quicker_id uuid,
  quicker text,
  cedula text,
  hora_inicio time,
  hora_fin time,
  tipo_contrato text default 'Fijo',
  tipo_gestion text default 'Fijo',
  quick_go_id text,
  quick_go_estado text,
  novedad_tipo text,
  observaciones text,
  aprobacion text default 'Pendiente',
  estado text default 'Programado',
  extra jsonb default '{}'::jsonb,
  creado_en timestamptz default now()
);

create table if not exists public.marcaciones (
  id uuid primary key default gen_random_uuid(),
  malla_id uuid not null references public.mallas(id) on delete cascade,
  tipo text not null check (tipo in ('ingreso','salida','almuerzo_inicio','almuerzo_fin')),
  fecha date not null,
  hora time not null,
  quicker_id uuid,
  quicker text,
  lat double precision,
  lng double precision,
  direccion text,
  registrado_por uuid references auth.users(id),
  registrado_en timestamptz default now(),
  unique (malla_id, tipo)
);

create table if not exists public.evidencias (
  id uuid primary key default gen_random_uuid(),
  malla_id uuid references public.mallas(id) on delete cascade,
  quicker text,
  etapa text,
  tipo text default 'Foto/GPS',
  foto_url text,
  direccion text,
  lat double precision,
  lng double precision,
  registrado_en timestamptz default now()
);

create table if not exists public.ubicaciones (
  id bigint generated always as identity primary key,
  malla_id uuid references public.mallas(id) on delete set null,
  quicker_id uuid,
  quicker text not null,
  cliente text,
  punto text,
  lat double precision not null,
  lng double precision not null,
  registrado_en timestamptz default now()
);

create table if not exists public.matriz_activos (
  clave text primary key,
  filas jsonb not null default '[]'::jsonb,
  actualizado_en timestamptz default now()
);

insert into storage.buckets (id, name, public)
values ('evidencias', 'evidencias', true)
on conflict (id) do update set public = excluded.public;

alter table public.mallas enable row level security;
alter table public.marcaciones enable row level security;
alter table public.evidencias enable row level security;
alter table public.ubicaciones enable row level security;
alter table public.matriz_activos enable row level security;

alter table public.perfiles enable row level security;
drop policy if exists "cada usuario actualiza su perfil" on public.perfiles;
create policy "cada usuario actualiza su perfil" on public.perfiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());

alter table public.quickers enable row level security;
drop policy if exists "quicker actualiza sus documentos" on public.quickers;
create policy "quicker actualiza sus documentos" on public.quickers for update to authenticated
using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());
drop policy if exists "administrativos revisan documentos quicker" on public.quickers;
create policy "administrativos revisan documentos quicker" on public.quickers for update to authenticated
using (exists (select 1 from public.perfiles p where p.id = auth.uid() and p.perfil in ('Administrador','Gerencia','Jefe','Coordinador','HSQ')))
with check (exists (select 1 from public.perfiles p where p.id = auth.uid() and p.perfil in ('Administrador','Gerencia','Jefe','Coordinador','HSQ')));

drop policy if exists "usuarios autenticados leen mallas" on public.mallas;
create policy "usuarios autenticados leen mallas" on public.mallas for select to authenticated using (true);
drop policy if exists "administrativos gestionan mallas" on public.mallas;
create policy "administrativos gestionan mallas" on public.mallas for all to authenticated
using (exists (select 1 from public.perfiles p where p.id = auth.uid() and p.perfil in ('Administrador','Gerencia','Jefe','Coordinador','HSQ')))
with check (exists (select 1 from public.perfiles p where p.id = auth.uid() and p.perfil in ('Administrador','Gerencia','Jefe','Coordinador','HSQ')));

drop policy if exists "autenticados gestionan marcaciones" on public.marcaciones;
create policy "autenticados gestionan marcaciones" on public.marcaciones for all to authenticated using (true) with check (true);
drop policy if exists "autenticados gestionan evidencias" on public.evidencias;
create policy "autenticados gestionan evidencias" on public.evidencias for all to authenticated using (true) with check (true);
drop policy if exists "autenticados registran ubicaciones" on public.ubicaciones;
create policy "autenticados registran ubicaciones" on public.ubicaciones for insert to authenticated with check (auth.uid() is not null);
drop policy if exists "autenticados leen ubicaciones" on public.ubicaciones;
create policy "autenticados leen ubicaciones" on public.ubicaciones for select to authenticated using (true);
drop policy if exists "administrativos gestionan matriz" on public.matriz_activos;
create policy "administrativos gestionan matriz" on public.matriz_activos for all to authenticated
using (exists (select 1 from public.perfiles p where p.id = auth.uid() and p.perfil in ('Administrador','Gerencia','Jefe','Coordinador','HSQ')))
with check (exists (select 1 from public.perfiles p where p.id = auth.uid() and p.perfil in ('Administrador','Gerencia','Jefe','Coordinador','HSQ')));

drop policy if exists "autenticados leen evidencias storage" on storage.objects;
create policy "autenticados leen evidencias storage" on storage.objects for select to authenticated using (bucket_id = 'evidencias');
drop policy if exists "autenticados suben evidencias storage" on storage.objects;
create policy "autenticados suben evidencias storage" on storage.objects for insert to authenticated with check (bucket_id = 'evidencias' and (storage.foldername(name))[1] = auth.uid()::text);

-- Para comenzar mallas/marcaciones desde cero, ejecutar conscientemente estas líneas
-- solo después de verificar que no haya información nueva que se deba conservar:
-- truncate table public.evidencias, public.marcaciones, public.ubicaciones, public.mallas restart identity cascade;
