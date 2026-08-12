-- 35 · Qué no puede comer esta persona.
--
-- Preferencias, alergias e intolerancias y condiciones médicas. No entran en
-- ninguna fórmula: entran en lo que "¿Qué como?" **puede proponer**. Sin esto,
-- la pantalla le ofrecía tarta de jamón y queso a alguien vegano y milanesa
-- rebozada a alguien celíaco.
--
-- Van en `profiles` y no en una tabla aparte porque son cero o unas pocas
-- etiquetas por persona, se leen siempre juntas con el resto del perfil y no
-- tienen historia: lo que importa es lo que la persona no puede comer **hoy**.
--
-- El documento local ya las guarda y viajan en el respaldo JSON; estas columnas
-- son para el otro camino, el de las tablas. Hacen falta porque al abrir la app
-- en un teléfono nuevo el perfil se arma con la fila de `profiles` —el respaldo
-- solo entra si las tablas no trajeron nada—, así que sin columna una alergia
-- cargada en un teléfono no existiría en el siguiente. Y eso es exactamente el
-- dato que no se puede perder al cambiar de teléfono.

alter table public.profiles
  add column if not exists dietary_flags text[] not null default '{}',
  add column if not exists dietary_note  text;

-- El texto libre existe para la alergia que no está en la lista de ocho. Se
-- acota el largo acá también: la app corta en 200, y una columna sin techo es
-- una invitación a que alguien escriba un libro que después hay que meter en
-- cada prompt.
alter table public.profiles
  drop constraint if exists profiles_dietary_note_len;
alter table public.profiles
  add constraint profiles_dietary_note_len
    check (dietary_note is null or char_length(dietary_note) <= 200);

-- Y un techo a la cantidad de etiquetas: son ocho las que ofrece la app, así
-- que más que eso es un cliente roto o alguien probando.
alter table public.profiles
  drop constraint if exists profiles_dietary_flags_len;
alter table public.profiles
  add constraint profiles_dietary_flags_len
    check (array_length(dietary_flags, 1) is null
        or array_length(dietary_flags, 1) <= 16);

-- No se abre a nadie más de lo que ya estaba abierto: `profiles` sigue con las
-- policies de la migración 28, donde lo único que ve un pal es la vista
-- `pal_profiles` (id y nombre). Una alergia es un dato de salud y no sale de
-- acá salvo hacia la propia cuenta.

-- down
-- alter table public.profiles
--   drop constraint if exists profiles_dietary_flags_len,
--   drop constraint if exists profiles_dietary_note_len,
--   drop column if exists dietary_note,
--   drop column if exists dietary_flags;
