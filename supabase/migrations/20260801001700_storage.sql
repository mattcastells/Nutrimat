-- 18 · Buckets de Storage (08-supabase-plan.md §3).
--
-- Las fotos no van a Postgres: van a Storage, y en la tabla queda solo la
-- ruta (`photo_path`, que ya existe en meals, activities, ai_analyses y
-- body_measurements desde las migraciones 5, 6, 9 y 11).
--
-- Los tres buckets son **privados**. La app nunca sirve una URL pública: pide
-- una URL firmada de 1 hora cada vez que necesita mostrar una imagen. Una foto
-- de lo que alguien come es un dato de salud; una URL pública, aunque tenga un
-- nombre imposible de adivinar, es para siempre y no se puede revocar.

-- ── Buckets ───────────────────────────────────────────────────────────────
-- 8 MB alcanza de sobra para una foto de teléfono ya comprimida y pone un
-- techo a lo que puede subir una cuenta comprometida.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'meal-photos', 'meal-photos', false, 8388608,
    array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
  ),
  (
    'activity-photos', 'activity-photos', false, 8388608,
    array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
  ),
  (
    'progress-photos', 'progress-photos', false, 8388608,
    array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
  )
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── Políticas por prefijo ─────────────────────────────────────────────────
-- La convención de ruta es `{user_id}/{registro_id}.jpg`, así que la primera
-- carpeta del nombre **es** el dueño. `storage.foldername(name)[1]` la extrae
-- y se compara contra `auth.uid()`.
--
-- Sin `with check`, alguien podría escribir dentro de la carpeta de otro
-- aunque no pudiera leerla: `using` filtra lo que se ve, `with check` valida
-- lo que se escribe. Van los dos.
do $$
declare
  b text;
begin
  foreach b in array array['meal-photos', 'activity-photos', 'progress-photos']
  loop
    execute format($p$
      drop policy if exists %I on storage.objects;
      create policy %I on storage.objects
        for all to authenticated
        using (
          bucket_id = %L
          and (storage.foldername(name))[1] = (select auth.uid())::text
        )
        with check (
          bucket_id = %L
          and (storage.foldername(name))[1] = (select auth.uid())::text
        );
    $p$, b || '_own_folder_rw', b || '_own_folder_rw', b, b);
  end loop;
end $$;
