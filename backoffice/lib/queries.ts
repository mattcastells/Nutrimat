import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Lo que el panel lee de un paciente.
 *
 * Todas las consultas filtran por `user_id` **además** de apoyarse en RLS. No
 * es redundancia defensiva por gusto: sin el filtro, una tabla que mañana sume
 * una policy nueva empezaría a devolver filas de otra persona en esta misma
 * pantalla, y el bug se vería como "datos mezclados" y no como un permiso mal
 * puesto.
 *
 * Cuando una categoría no está concedida la consulta no falla: devuelve vacío.
 * Por eso la pantalla distingue "no compartido" de "sin registros" con el flag
 * del permiso, no con el largo del resultado.
 */

export type Meal = {
  id: string;
  slot: string;
  local_date: string;
  logged_at: string;
  name: string | null;
  total_kcal: number;
  total_protein_g: number;
  total_carbs_g: number;
  total_fat_g: number;
  source: string;
  photo_path: string | null;
  meal_items: MealItem[];
};

export type MealItem = {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  ai_confidence: number | null;
};

export type WeightLog = { local_date: string; weight_kg: number };
export type WaterLog = { local_date: string; glasses: number };
export type SleepLog = { local_date: string; minutes: number; quality: string | null };
export type Activity = {
  id: string;
  local_date: string;
  started_at: string;
  duration_minutes: number;
  estimated_calories: number | null;
  intensity: string;
};
export type Goal = { target_kcal: number | null; protein_g: number | null };

export const SLOT_LABEL: Record<string, string> = {
  breakfast: 'Desayuno',
  lunch: 'Almuerzo',
  dinner: 'Cena',
  snack: 'Snacks',
};

export async function fetchMeals(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<Meal[]> {
  const { data } = await db
    .from('meals')
    .select(
      'id, slot, local_date, logged_at, name, total_kcal, total_protein_g, ' +
        'total_carbs_g, total_fat_g, source, photo_path, ' +
        'meal_items(id, name, quantity, unit, kcal, protein_g, carbs_g, ' +
        'fat_g, ai_confidence)',
    )
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date', { ascending: false })
    .order('logged_at', { ascending: true });

  return (data ?? []) as unknown as Meal[];
}

export async function fetchWeights(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<WeightLog[]> {
  const { data } = await db
    .from('weight_logs')
    .select('local_date, weight_kg')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date');

  return (data ?? []) as unknown as WeightLog[];
}

export async function fetchWater(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<WaterLog[]> {
  const { data } = await db
    .from('water_logs')
    .select('local_date, glasses')
    .eq('user_id', userId)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date');

  return (data ?? []) as unknown as WaterLog[];
}

export async function fetchActivities(
  db: SupabaseClient,
  userId: string,
  from: string,
  to: string,
): Promise<Activity[]> {
  const { data } = await db
    .from('activities')
    .select(
      'id, local_date, started_at, duration_minutes, estimated_calories, intensity',
    )
    .eq('user_id', userId)
    .is('deleted_at', null)
    .gte('local_date', from)
    .lte('local_date', to)
    .order('local_date', { ascending: false });

  return (data ?? []) as unknown as Activity[];
}

export async function fetchGoal(
  db: SupabaseClient,
  userId: string,
): Promise<Goal | null> {
  const { data } = await db
    .from('goals')
    .select('target_kcal, protein_g')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  return (data ?? null) as unknown as Goal | null;
}

/**
 * URLs firmadas para las fotos del bucket privado.
 *
 * Se firman del lado del servidor y duran una hora: una URL de foto de comida
 * que no vence es una foto pública con dirección difícil de adivinar, que no es
 * lo mismo que una foto privada.
 */
export async function signPhotos(
  db: SupabaseClient,
  paths: string[],
): Promise<Record<string, string>> {
  const unique = [...new Set(paths.filter(Boolean))];
  if (unique.length === 0) return {};

  const { data } = await db.storage
    .from('meal-photos')
    .createSignedUrls(unique, 60 * 60);

  const out: Record<string, string> = {};
  for (const row of data ?? []) {
    // `path` viene null si esa foto puntual no se pudo firmar —por ejemplo si
    // la categoría no está concedida—. Se saltea sin romper el resto.
    if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
  }
  return out;
}
