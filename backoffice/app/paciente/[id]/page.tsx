import Link from 'next/link';
import { notFound } from 'next/navigation';
import { serverClient } from '@/lib/supabase';
import {
  fetchActivities,
  fetchGoal,
  fetchMeals,
  fetchWater,
  fetchWeights,
  signPhotos,
  SLOT_LABEL,
  type Meal,
} from '@/lib/queries';
import { WeightChart } from '@/components/weight-chart';
import { CaloriesChart } from '@/components/calories-chart';
import { RangePicker } from '@/components/range-picker';

export const dynamic = 'force-dynamic';

const RANGES: Record<string, number> = { '7': 7, '30': 30, '90': 90 };

export default async function PatientPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ dias?: string }>;
}) {
  const { id } = await params;
  const { dias } = await searchParams;
  const days = RANGES[dias ?? '30'] ?? 30;

  const supabase = await serverClient();

  // La ficha sale de `care_patients`, que ya filtra por permiso vigente. Si no
  // hay fila, no hay acceso: no se distingue de "no existe" a propósito, porque
  // decir "existe pero no podés verlo" ya cuenta algo sobre esa persona.
  const { data: row } = await supabase
    .from('care_patients')
    .select(
      'patient_id, patient_name, share_meals, share_photos, share_body, ' +
        'share_wellbeing',
    )
    .eq('patient_id', id)
    .maybeSingle();

  if (!row) notFound();

  const patient = row as unknown as {
    patient_id: string;
    patient_name: string | null;
    share_meals: boolean;
    share_photos: boolean;
    share_body: boolean;
    share_wellbeing: boolean;
  };

  const to = hoy();
  const from = hace(days);

  const [meals, weights, water, activities, goal] = await Promise.all([
    patient.share_meals ? fetchMeals(supabase, id, from, to) : [],
    patient.share_body ? fetchWeights(supabase, id, from, to) : [],
    patient.share_wellbeing ? fetchWater(supabase, id, from, to) : [],
    patient.share_wellbeing ? fetchActivities(supabase, id, from, to) : [],
    patient.share_meals ? fetchGoal(supabase, id) : null,
  ]);

  const photoUrls = patient.share_photos
    ? await signPhotos(
        supabase,
        meals.map((m) => m.photo_path).filter((p): p is string => !!p),
      )
    : {};

  const porDia = agruparPorDia(meals);
  const kcalPorDia = [...porDia.entries()]
    .map(([date, ms]) => ({
      date,
      kcal: ms.reduce((a, m) => a + m.total_kcal, 0),
    }))
    .sort((a, b) => a.date.localeCompare(b.date));

  return (
    <main className="page">
      <p className="caption">
        <Link href="/">← Pacientes</Link>
      </p>

      <div
        className="row"
        style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}
      >
        <h1>{patient.patient_name || 'Sin nombre'}</h1>
        <RangePicker current={String(days)} />
      </div>

      {/* ── Calorías ─────────────────────────────────────────────────── */}
      <div className="section-header">Calorías por día</div>
      {patient.share_meals ? (
        <div className="card">
          <CaloriesChart days={kcalPorDia} target={goal?.target_kcal ?? null} />
        </div>
      ) : (
        <NoCompartido que="Las comidas" />
      )}

      {/* ── Peso ─────────────────────────────────────────────────────── */}
      <div className="section-header">Peso</div>
      {patient.share_body ? (
        <div className="card">
          <WeightChart logs={weights} />
        </div>
      ) : (
        <NoCompartido que="El peso y las medidas" />
      )}

      {/* ── Día a día ────────────────────────────────────────────────── */}
      <div className="section-header">Día a día</div>
      {!patient.share_meals && <NoCompartido que="Las comidas" />}

      {patient.share_meals && porDia.size === 0 && (
        <div className="card">
          <p className="muted">Sin comidas cargadas en este período.</p>
        </div>
      )}

      {patient.share_meals &&
        [...porDia.entries()]
          .sort((a, b) => b[0].localeCompare(a[0]))
          .map(([date, ms]) => {
            const total = ms.reduce((a, m) => a + m.total_kcal, 0);
            const agua = water.find((w) => w.local_date === date);
            const act = activities.filter((a) => a.local_date === date);

            return (
              <div key={date} className="card" style={{ marginBottom: 'var(--s4)' }}>
                <div
                  className="row"
                  style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}
                >
                  <h3>{fechaLarga(date)}</h3>
                  <span className="tnum">
                    {total} kcal
                    {goal?.target_kcal ? (
                      <span className="muted"> de {goal.target_kcal}</span>
                    ) : null}
                  </span>
                </div>

                {ms.map((m) => (
                  <div key={m.id} style={{ marginTop: 'var(--s4)' }}>
                    <hr className="divider" />
                    <div
                      className="row"
                      style={{
                        justifyContent: 'space-between',
                        marginTop: 'var(--s3)',
                        flexWrap: 'wrap',
                      }}
                    >
                      <div>
                        <strong>{SLOT_LABEL[m.slot] ?? m.slot}</strong>
                        {m.name ? <span className="muted"> · {m.name}</span> : null}
                        {esIA(m) && (
                          <span className="tag tag--ai" style={{ marginLeft: 8 }}>
                            Estimado por IA
                          </span>
                        )}
                      </div>
                      <span className="tnum">{m.total_kcal} kcal</span>
                    </div>

                    <div className="scroll-x" style={{ marginTop: 'var(--s2)' }}>
                      <table>
                        <thead>
                          <tr>
                            <th>Ítem</th>
                            <th style={{ textAlign: 'right' }}>Cant.</th>
                            <th style={{ textAlign: 'right' }}>kcal</th>
                            <th style={{ textAlign: 'right' }}>P</th>
                            <th style={{ textAlign: 'right' }}>C</th>
                            <th style={{ textAlign: 'right' }}>G</th>
                          </tr>
                        </thead>
                        <tbody>
                          {m.meal_items.map((it) => (
                            <tr key={it.id}>
                              <td>
                                {it.name}
                                {it.ai_confidence !== null &&
                                  it.ai_confidence < 0.5 && (
                                    <span
                                      className="caption estimate"
                                      style={{ marginLeft: 6 }}
                                    >
                                      confianza baja
                                    </span>
                                  )}
                              </td>
                              <td className="tnum" style={{ textAlign: 'right' }}>
                                {fmt(it.quantity)} {it.unit}
                              </td>
                              <td className="tnum" style={{ textAlign: 'right' }}>
                                {it.kcal}
                              </td>
                              <td className="tnum" style={{ textAlign: 'right' }}>
                                {fmt(it.protein_g)}
                              </td>
                              <td className="tnum" style={{ textAlign: 'right' }}>
                                {fmt(it.carbs_g)}
                              </td>
                              <td className="tnum" style={{ textAlign: 'right' }}>
                                {fmt(it.fat_g)}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>

                    {m.photo_path && photoUrls[m.photo_path] && (
                      /* eslint-disable-next-line @next/next/no-img-element */
                      <img
                        src={photoUrls[m.photo_path]}
                        alt={`Foto de ${SLOT_LABEL[m.slot] ?? m.slot}`}
                        style={{
                          marginTop: 'var(--s3)',
                          maxWidth: 260,
                          width: '100%',
                          borderRadius: 'var(--radius-md)',
                          display: 'block',
                        }}
                      />
                    )}
                  </div>
                ))}

                {patient.share_wellbeing && (agua || act.length > 0) && (
                  <p className="caption" style={{ marginTop: 'var(--s4)' }}>
                    {agua ? `${agua.glasses} vasos de agua` : null}
                    {agua && act.length > 0 ? ' · ' : null}
                    {act.length > 0
                      ? `${act.length} ${act.length === 1 ? 'actividad' : 'actividades'}, ` +
                        `≈ ${act.reduce((a, x) => a + (x.estimated_calories ?? 0), 0)} kcal`
                      : null}
                  </p>
                )}
              </div>
            );
          })}

      <p className="caption" style={{ marginTop: 'var(--s7)' }}>
        Las calorías del ejercicio y lo estimado por IA son estimaciones, no
        mediciones. Este panel es de solo lectura: nada de lo que ves se puede
        modificar desde acá.
      </p>
    </main>
  );
}

/** Una categoría apagada no es lo mismo que un día sin registros, y decirlo
 *  evita leer un vacío como "no comió". */
function NoCompartido({ que }: { que: string }) {
  return (
    <div className="card">
      <p className="muted">
        {que} no {que.includes('y') ? 'están' : 'está'} compartido. Se prende
        desde la app, en Perfil → Mi nutricionista.
      </p>
    </div>
  );
}

function esIA(m: Meal): boolean {
  return m.source === 'ai_photo' || m.source === 'ai_text';
}

function agruparPorDia(meals: Meal[]): Map<string, Meal[]> {
  const out = new Map<string, Meal[]>();
  for (const m of meals) {
    const list = out.get(m.local_date) ?? [];
    list.push(m);
    out.set(m.local_date, list);
  }
  return out;
}

function fmt(v: number): string {
  const n = Number(v);
  return Number.isInteger(n) ? String(n) : n.toFixed(1).replace('.', ',');
}

function hoy(): string {
  return new Date().toISOString().slice(0, 10);
}

function hace(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().slice(0, 10);
}

function fechaLarga(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('es-AR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
}
