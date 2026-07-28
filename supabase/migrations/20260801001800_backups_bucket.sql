-- 19 · Bucket de respaldos.
--
-- El respaldo se guardaba en `progress-photos` para no sumar una migración por
-- un solo archivo. No funcionó: ese bucket restringe los MIME a imágenes, así
-- que la subida del JSON se rechazaba. Va en el suyo.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('backups', 'backups', false, 52428800, array['application/json'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Misma política por prefijo que los buckets de fotos: la primera carpeta del
-- nombre es el dueño.
drop policy if exists backups_own_folder_rw on storage.objects;
create policy backups_own_folder_rw on storage.objects
  for all to authenticated
  using (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'backups'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
