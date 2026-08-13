-- ============================================================================
--  CORRECCIÓN DE SEGURIDAD — ejecutar en el SQL Editor del proyecto
--
--  Corrige dos problemas detectados tras la migración:
--
--  1) La cubeta "evidencias" quedó PÚBLICA. Se verificó que los documentos
--     (cédula, licencia, SOAT, fotos) se descargaban desde internet sin
--     iniciar sesión, solo con la dirección del archivo.
--
--  2) Se agregaron políticas con "using (true)" sobre mallas, marcaciones,
--     evidencias y ubicaciones. Como las políticas permisivas se suman entre
--     sí, esas anulan en la práctica el control por operación y por perfil:
--     cualquier usuario con sesión podía leer, modificar o borrar la
--     información de cualquier otro, incluidas las marcaciones que sustentan
--     la nómina.
--
--  Requiere que la aplicación ya use enlaces firmados en vez de URL públicas.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────
-- 1. La cubeta deja de ser pública
-- ─────────────────────────────────────────────────────────────
update storage.buckets set public = false where id = 'evidencias';

-- Solo el dueño del archivo o el personal administrativo puede verlo
drop policy if exists "autenticados leen evidencias storage" on storage.objects;
create policy "lectura de evidencias por dueno o administrativo"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'evidencias'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.es_gestor()
    )
  );

-- Cada quien sube en su propia carpeta (se conserva la regla existente)
drop policy if exists "autenticados suben evidencias storage" on storage.objects;
create policy "cada usuario sube en su carpeta"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'evidencias' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "solo administrador borra evidencias storage" on storage.objects;
create policy "solo administrador borra evidencias storage"
  on storage.objects for delete to authenticated
  using (bucket_id = 'evidencias' and public.es_admin());


-- ─────────────────────────────────────────────────────────────
-- 2. Se retiran las políticas abiertas
--    Las políticas por operación y perfil del esquema original
--    siguen existiendo y vuelven a ser las que mandan.
-- ─────────────────────────────────────────────────────────────
drop policy if exists "usuarios autenticados leen mallas"      on public.mallas;
drop policy if exists "administrativos gestionan mallas"       on public.mallas;
drop policy if exists "autenticados gestionan marcaciones"     on public.marcaciones;
drop policy if exists "autenticados gestionan evidencias"      on public.evidencias;
drop policy if exists "autenticados leen ubicaciones"          on public.ubicaciones;
drop policy if exists "autenticados registran ubicaciones"     on public.ubicaciones;


-- ─────────────────────────────────────────────────────────────
-- 3. Se reponen las reglas correctas donde hagan falta
--    (idempotente: se puede ejecutar más de una vez sin daño)
-- ─────────────────────────────────────────────────────────────

-- Mallas: el mensajero ve las suyas; el resto por operación asignada
drop policy if exists "mallas: el mensajero ve sus turnos" on public.mallas;
create policy "mallas: el mensajero ve sus turnos"
  on public.mallas for select to authenticated
  using (quicker_id in (select id from public.quickers where usuario_id = auth.uid()));

drop policy if exists "mallas: lectura por alcance" on public.mallas;
create policy "mallas: lectura por alcance"
  on public.mallas for select to authenticated
  using (public.es_gestor() and public.puede_ver_operacion(cliente));

drop policy if exists "mallas: gestores crean en su operacion" on public.mallas;
create policy "mallas: gestores crean en su operacion"
  on public.mallas for insert to authenticated
  with check (public.es_gestor() and public.puede_ver_operacion(cliente));

drop policy if exists "mallas: gestores actualizan en su operacion" on public.mallas;
create policy "mallas: gestores actualizan en su operacion"
  on public.mallas for update to authenticated
  using (public.es_gestor() and public.puede_ver_operacion(cliente))
  with check (public.es_gestor() and public.puede_ver_operacion(cliente));

drop policy if exists "mallas: solo administrador elimina" on public.mallas;
create policy "mallas: solo administrador elimina"
  on public.mallas for delete to authenticated using (public.es_admin());

-- Marcaciones: el mensajero solo marca su propio turno; corregir o borrar
-- es potestad del administrador. Es la información que sustenta la nómina.
drop policy if exists "marcaciones: el mensajero ve las suyas" on public.marcaciones;
create policy "marcaciones: el mensajero ve las suyas"
  on public.marcaciones for select to authenticated
  using (quicker_id in (select id from public.quickers where usuario_id = auth.uid()));

drop policy if exists "marcaciones: lectura por alcance" on public.marcaciones;
create policy "marcaciones: lectura por alcance"
  on public.marcaciones for select to authenticated
  using (public.es_gestor() and exists (
    select 1 from public.mallas m
    where m.id = marcaciones.malla_id and public.puede_ver_operacion(m.cliente)));

drop policy if exists "marcaciones: el mensajero marca su propio turno" on public.marcaciones;
create policy "marcaciones: el mensajero marca su propio turno"
  on public.marcaciones for insert to authenticated
  with check (exists (
    select 1 from public.mallas m
    join public.quickers q on q.id = m.quicker_id
    where m.id = marcaciones.malla_id and q.usuario_id = auth.uid()));

drop policy if exists "marcaciones: gestores registran en su operacion" on public.marcaciones;
create policy "marcaciones: gestores registran en su operacion"
  on public.marcaciones for insert to authenticated
  with check (public.es_gestor() and exists (
    select 1 from public.mallas m
    where m.id = marcaciones.malla_id and public.puede_ver_operacion(m.cliente)));

drop policy if exists "marcaciones: solo administrador corrige" on public.marcaciones;
create policy "marcaciones: solo administrador corrige"
  on public.marcaciones for update to authenticated
  using (public.es_admin()) with check (public.es_admin());

drop policy if exists "marcaciones: solo administrador elimina" on public.marcaciones;
create policy "marcaciones: solo administrador elimina"
  on public.marcaciones for delete to authenticated using (public.es_admin());

-- Evidencias fotográficas
drop policy if exists "evidencias: el mensajero ve las suyas" on public.evidencias;
create policy "evidencias: el mensajero ve las suyas"
  on public.evidencias for select to authenticated
  using (quicker = (select nombre from public.perfiles where id = auth.uid()));

drop policy if exists "evidencias: lectura por alcance" on public.evidencias;
create policy "evidencias: lectura por alcance"
  on public.evidencias for select to authenticated
  using (public.es_gestor());

drop policy if exists "evidencias: insercion autenticada" on public.evidencias;
create policy "evidencias: insercion autenticada"
  on public.evidencias for insert to authenticated with check (auth.uid() is not null);

drop policy if exists "evidencias: solo administrador elimina" on public.evidencias;
create policy "evidencias: solo administrador elimina"
  on public.evidencias for delete to authenticated using (public.es_admin());

-- Ubicaciones GPS: son datos personales del trabajador
drop policy if exists "ubicaciones: el mensajero registra la suya" on public.ubicaciones;
create policy "ubicaciones: el mensajero registra la suya"
  on public.ubicaciones for insert to authenticated
  with check (auth.uid() is not null);

drop policy if exists "ubicaciones: el mensajero ve las suyas" on public.ubicaciones;
create policy "ubicaciones: el mensajero ve las suyas"
  on public.ubicaciones for select to authenticated
  using (quicker_id in (select id from public.quickers where usuario_id = auth.uid()));

drop policy if exists "ubicaciones: lectura por alcance" on public.ubicaciones;
create policy "ubicaciones: lectura por alcance"
  on public.ubicaciones for select to authenticated
  using (public.es_gestor() and public.puede_ver_operacion(cliente));

drop policy if exists "ubicaciones: solo administrador purga" on public.ubicaciones;
create policy "ubicaciones: solo administrador purga"
  on public.ubicaciones for delete to authenticated using (public.es_admin());


-- ─────────────────────────────────────────────────────────────
-- Comprobación: la cubeta debe quedar en "false"
-- ─────────────────────────────────────────────────────────────
select id, public as es_publica from storage.buckets where id = 'evidencias';
