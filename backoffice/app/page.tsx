import { serverClient } from '@/lib/supabase';
import { haceISO, hoyISO, rangoDeFechas } from '@/lib/format';
import { PatientsList, type PatientRow } from '@/components/patients-list';

export const dynamic = 'force-dynamic';

/**
 * La lista, y la última semana de cada uno.
 *
 * La semana sale de **una sola consulta** para todos los pacientes, acotada a
 * siete días y a dos columnas: una por paciente sería una cascada de pedidos
 * que crece con la cartera, y traer las comidas enteras sería bajar el detalle
 * de cada ítem para dibujar siete puntitos.
 *
 * Si la consulta falla, la lista se muestra igual sin la semana. Que no se
 * sepa quién dejó de registrar es peor que la lista completa, pero es mucho
 * mejor que no poder entrar a ninguna ficha.
 */
export default async function PatientsPage() {
  const supabase = await serverClient();
  const { data, error } = await supabase
    .from('care_patients')
    .select(
      'grant_id, patient_id, patient_name, birth_date, share_meals, ' +
        'share_photos, share_body, share_wellbeing, expires_at',
    )
    .order('patient_name');

  const patients = (data ?? []) as unknown as PatientRow[];

  const hasta = hoyISO();
  const desde = haceISO(6);
  const ultimos = rangoDeFechas(desde, hasta);

  const conComidas = patients.filter((p) => p.share_meals).map((p) => p.patient_id);
  const diasConCarga: Record<string, string[]> = {};

  if (conComidas.length > 0) {
    const { data: recientes } = await supabase
      .from('meals')
      .select('user_id, local_date')
      .in('user_id', conComidas)
      .is('deleted_at', null)
      .gte('local_date', desde)
      .lte('local_date', hasta);

    for (const row of (recientes ?? []) as { user_id: string; local_date: string }[]) {
      const ya = diasConCarga[row.user_id] ?? [];
      if (!ya.includes(row.local_date)) ya.push(row.local_date);
      diasConCarga[row.user_id] = ya;
    }
  }

  return (
    <PatientsList
      patients={patients}
      ultimos={ultimos}
      diasConCarga={diasConCarga}
      error={!!error}
    />
  );
}
