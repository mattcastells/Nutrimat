import { notFound } from 'next/navigation';
import { serverClient } from '@/lib/supabase';
import {
  fetchActivities,
  fetchGoal,
  fetchMeals,
  fetchMeasurements,
  fetchSleep,
  fetchWater,
  fetchWeights,
  signPhotos,
} from '@/lib/queries';
import { hoyISO, haceISO } from '@/lib/format';
import {
  PatientView,
  type PatientProfile,
} from '@/components/patient-view';

export const dynamic = 'force-dynamic';

const RANGES: Record<string, number> = {
  '7': 7,
  '30': 30,
  '90': 90,
  '365': 365,
};

/**
 * Todo lo que la ficha necesita, pedido una sola vez.
 *
 * Acá solo se consulta: el armado de la pantalla es `PatientView`, que es una
 * función de los datos y no sabe de Supabase. Esa frontera es la que permite
 * mirar el diseño con datos de ejemplo sin duplicar la maqueta.
 *
 * Todo se pide junto y las cinco pestañas se renderizan de una. Cambiar de
 * pestaña no vuelve al servidor; cambiar el período sí, porque ahí cambian los
 * datos.
 */
export default async function PatientPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ dias?: string; t?: string }>;
}) {
  const { id } = await params;
  const { dias, t } = await searchParams;
  const days = RANGES[dias ?? '30'] ?? 30;

  const supabase = await serverClient();

  // La ficha sale de `care_patients`, que ya filtra por permiso vigente. Sin
  // fila no hay acceso, y no se distingue de "no existe" a propósito: decir
  // "existe pero no podés verlo" ya cuenta algo sobre esa persona.
  const { data: row } = await supabase
    .from('care_patients')
    .select(
      'patient_id, patient_name, birth_date, height_cm, share_meals, ' +
        'share_photos, share_body, share_wellbeing',
    )
    .eq('patient_id', id)
    .maybeSingle();

  if (!row) notFound();

  const p = row as unknown as PatientProfile;

  const to = hoyISO();
  // `days - 1` porque hoy cuenta: "últimos 7 días" son siete cuadrados en el
  // calendario y siete en "días con comidas de 7", no ocho.
  const from = haceISO(days - 1);

  const [meals, weights, water, activities, sleep, measurements, goal] =
    await Promise.all([
      p.share_meals ? fetchMeals(supabase, id, from, to) : [],
      p.share_body ? fetchWeights(supabase, id, from, to) : [],
      p.share_wellbeing ? fetchWater(supabase, id, from, to) : [],
      p.share_wellbeing ? fetchActivities(supabase, id, from, to) : [],
      p.share_wellbeing ? fetchSleep(supabase, id, from, to) : [],
      p.share_body ? fetchMeasurements(supabase, id, from, to) : [],
      p.share_meals ? fetchGoal(supabase, id) : null,
    ]);

  const photoUrls = p.share_photos
    ? await signPhotos(
        supabase,
        meals.map((m) => m.photo_path).filter((x): x is string => !!x),
      )
    : {};

  return (
    <PatientView
      tab={t}
      data={{
        patient: p,
        days,
        from,
        to,
        meals,
        weights,
        water,
        activities,
        sleep,
        measurements,
        goal,
        photoUrls,
      }}
    />
  );
}
