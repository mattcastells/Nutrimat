-- 07b · Seed de activity_types desde met-catalog.json (07-data-model.md §7).
--
-- Es una migración de **datos** con `on conflict (slug) do update`: permite
-- ajustar un MET sin publicar la app y sin duplicar filas (D-06).
-- Los 15 tipos del MVP, idénticos a docs/handoff/met-catalog.json.

insert into public.activity_types (
  slug, display_name, category, default_met, light_met, moderate_met,
  vigorous_met, supports_distance, supports_steps, supports_heart_rate,
  icon_name, is_system
)
values
  ('walking',             'Caminata',                  'cardio',   3.5, 2.8, 3.5,  5.0,  true,  true,  true,  'PersonSimpleWalk',   true),
  ('running',             'Carrera',                   'cardio',   9.8, 7.0, 9.8,  12.3, true,  true,  true,  'PersonSimpleRun',    true),
  ('cycling',             'Ciclismo',                  'cardio',   7.5, 4.0, 7.5,  10.0, true,  false, true,  'PersonSimpleBike',   true),
  ('swimming',            'Natación',                  'cardio',   6.0, 4.5, 6.0,  9.8,  true,  false, false, 'PersonSimpleSwim',   true),
  ('strength_training',   'Entrenamiento de fuerza',   'strength', 5.0, 3.5, 5.0,  6.0,  false, false, true,  'Barbell',            true),
  ('functional_training', 'Entrenamiento funcional',   'strength', 6.0, 4.0, 6.0,  8.0,  false, false, true,  'Boxing',             true),
  ('yoga',                'Yoga',                      'mobility', 2.5, 2.0, 2.5,  4.0,  false, false, false, 'PersonSimpleTaiChi', true),
  ('pilates',             'Pilates',                   'mobility', 3.0, 2.5, 3.0,  4.0,  false, false, false, 'PersonSimpleTaiChi', true),
  ('sports',              'Deportes',                  'sports',   7.0, 5.0, 7.0,  10.0, false, true,  true,  'SoccerBall',         true),
  ('dancing',             'Baile',                     'cardio',   5.0, 3.5, 5.0,  7.8,  false, true,  false, 'MusicNotes',         true),
  ('hiking',              'Senderismo',                'cardio',   6.0, 4.5, 6.0,  7.8,  true,  true,  true,  'Mountains',          true),
  ('elliptical',          'Elíptico',                  'cardio',   5.0, 4.0, 5.0,  7.0,  true,  false, true,  'Wind',               true),
  ('rowing',              'Remo',                      'cardio',   7.0, 4.8, 7.0,  8.5,  true,  false, true,  'Boat',               true),
  ('stairs',              'Escaleras',                 'cardio',   8.0, 4.0, 8.0,  11.0, false, true,  true,  'Stairs',             true),
  ('custom',              'Actividad personalizada',   'other',    4.0, 3.0, 4.0,  6.0,  true,  true,  true,  'DotsThreeCircle',    true)
on conflict (slug) do update set
  display_name        = excluded.display_name,
  category            = excluded.category,
  default_met         = excluded.default_met,
  light_met           = excluded.light_met,
  moderate_met        = excluded.moderate_met,
  vigorous_met        = excluded.vigorous_met,
  supports_distance   = excluded.supports_distance,
  supports_steps      = excluded.supports_steps,
  supports_heart_rate = excluded.supports_heart_rate,
  icon_name           = excluded.icon_name,
  updated_at          = now();

-- down
-- delete from public.activity_types where is_system;
