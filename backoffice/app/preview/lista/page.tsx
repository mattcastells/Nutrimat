/** La lista con datos de ejemplo. **Solo en desarrollo**: ver `app/preview/page.tsx`. */
import { notFound } from 'next/navigation';
import { PatientsList, type PatientRow } from '@/components/patients-list';
import { haceISO, hoyISO, rangoDeFechas } from '@/lib/format';

export const dynamic = 'force-dynamic';

const PACIENTES: PatientRow[] = [
  {
    grant_id: 'g1',
    patient_id: 'demo',
    patient_name: 'Ana Pérez',
    birth_date: '1989-04-12',
    share_meals: true,
    share_photos: true,
    share_body: true,
    share_wellbeing: true,
    expires_at: null,
  },
  {
    grant_id: 'g2',
    patient_id: 'demo2',
    patient_name: 'Bruno Gómez',
    birth_date: '1976-11-02',
    share_meals: true,
    share_photos: false,
    share_body: true,
    share_wellbeing: false,
    expires_at: null,
  },
  {
    grant_id: 'g3',
    patient_id: 'demo3',
    patient_name: 'Carla Suárez',
    birth_date: '2001-01-30',
    share_meals: false,
    share_photos: false,
    share_body: true,
    share_wellbeing: true,
    expires_at: '2026-12-31',
  },
];

export default function PreviewLista() {
  // Solo en desarrollo, por lo mismo que `app/preview/page.tsx`.
  if (process.env.NODE_ENV === 'production') notFound();

  const hasta = hoyISO();
  const ultimos = rangoDeFechas(haceISO(6), hasta);
  return (
    <PatientsList
      patients={PACIENTES}
      ultimos={ultimos}
      diasConCarga={{
        demo: ultimos.filter((_, i) => i !== 2 && i !== 5),
        demo2: ultimos.slice(0, 3),
      }}
    />
  );
}
