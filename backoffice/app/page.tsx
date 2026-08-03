import Link from 'next/link';
import { serverClient } from '@/lib/supabase';
import { SignOut } from '@/components/sign-out';
import { MyCode } from '@/components/my-code';

export const dynamic = 'force-dynamic';

type Patient = {
  grant_id: string;
  patient_id: string;
  patient_name: string | null;
  birth_date: string | null;
  share_meals: boolean;
  share_photos: boolean;
  share_body: boolean;
  share_wellbeing: boolean;
  expires_at: string | null;
};

/**
 * A quién puede seguir esta cuenta.
 *
 * Sale de `care_patients`, la vista de columnas contadas: acá no se consulta
 * `profiles` ni se filtra por permisos en el cliente. Lo que la lista muestra
 * es exactamente lo que la base devuelve, y lo que la base devuelve es lo que
 * cada paciente concedió.
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

  const patients = (data ?? []) as unknown as Patient[];

  return (
    <main className="page">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div>
          <h1>Pacientes</h1>
          <p className="muted" style={{ marginTop: 'var(--s2)' }}>
            Quienes te dieron acceso a su seguimiento.
          </p>
        </div>
        <SignOut />
      </div>

      <MyCode />

      {error && (
        <p style={{ color: 'var(--danger)', marginTop: 'var(--s6)' }}>
          No pudimos cargar la lista. Probá de nuevo en un rato.
        </p>
      )}

      {!error && patients.length === 0 && (
        <div className="card" style={{ marginTop: 'var(--s6)' }}>
          <h3>Todavía no te dio acceso nadie</h3>
          <p className="muted" style={{ marginTop: 'var(--s2)' }}>
            Pasale tu código de arriba a la persona que vas a seguir. Lo carga
            en la app, en Perfil → Mi nutricionista, y elige qué querés ver.
          </p>
        </div>
      )}

      {patients.length > 0 && (
        <>
          <div className="section-header">Con acceso vigente</div>
          <div className="grid">
            {patients.map((p) => (
              <Link
                key={p.grant_id}
                href={`/paciente/${p.patient_id}`}
                className="card"
                style={{ display: 'block', color: 'inherit' }}
              >
                <div className="row" style={{ justifyContent: 'space-between' }}>
                  <h3>{p.patient_name || 'Sin nombre'}</h3>
                  {p.birth_date && (
                    <span className="caption tnum">
                      {edad(p.birth_date)} años
                    </span>
                  )}
                </div>

                <div
                  className="row"
                  style={{ flexWrap: 'wrap', marginTop: 'var(--s3)' }}
                >
                  {categorias(p).map((c) => (
                    <span key={c} className="tag">
                      {c}
                    </span>
                  ))}
                  {categorias(p).length === 0 && (
                    <span className="tag" style={{ color: 'var(--caution)' }}>
                      Sin categorías: no vas a ver datos
                    </span>
                  )}
                </div>

                {p.expires_at && (
                  <p className="caption" style={{ marginTop: 'var(--s3)' }}>
                    El acceso vence el{' '}
                    {new Date(p.expires_at).toLocaleDateString('es-AR')}
                  </p>
                )}
              </Link>
            ))}
          </div>
        </>
      )}
    </main>
  );
}

function categorias(p: Patient): string[] {
  return [
    p.share_meals && 'Comidas',
    p.share_photos && 'Fotos',
    p.share_body && 'Peso y medidas',
    p.share_wellbeing && 'Actividad, agua y sueño',
  ].filter(Boolean) as string[];
}

function edad(birthDate: string): number {
  const nacimiento = new Date(birthDate);
  const hoy = new Date();
  let años = hoy.getFullYear() - nacimiento.getFullYear();
  const mes = hoy.getMonth() - nacimiento.getMonth();
  if (mes < 0 || (mes === 0 && hoy.getDate() < nacimiento.getDate())) años--;
  return años;
}
