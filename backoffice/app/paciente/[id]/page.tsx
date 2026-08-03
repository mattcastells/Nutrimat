import Link from 'next/link';
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
  METRIC_LABEL,
  type Meal,
} from '@/lib/queries';
import { WeightChart } from '@/components/weight-chart';
import { CaloriesChart } from '@/components/calories-chart';
import { BarChart, type Point } from '@/components/bar-chart';
import { DayCard, horas } from '@/components/day-card';
import { Stat, StatRow, Section } from '@/components/stat';
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

  const p = row as unknown as {
    patient_id: string;
    patient_name: string | null;
    birth_date: string | null;
    height_cm: number | null;
    share_meals: boolean;
    share_photos: boolean;
    share_body: boolean;
    share_wellbeing: boolean;
  };

  const to = hoy();
  const from = hace(days);

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

  const target = goal?.base_calorie_target ?? null;

  // Se recorren los días del período y no solo los que tienen algo: un hueco
  // es información —"no registró"— y una lista que salta del 3 al 7 lo esconde.
  const fechas = rango(from, to);
  const porDia = new Map<string, Meal[]>();
  for (const m of meals) {
    porDia.set(m.local_date, [...(porDia.get(m.local_date) ?? []), m]);
  }

  const kcalPorDia: Point[] = fechas
    .filter((d) => porDia.has(d))
    .map((d) => ({
      date: d,
      value: (porDia.get(d) ?? []).reduce((a, m) => a + m.total_kcal, 0),
    }));

  const diasConComida = kcalPorDia.length;
  const promedioKcal = diasConComida
    ? Math.round(kcalPorDia.reduce((a, x) => a + x.value, 0) / diasConComida)
    : 0;
  const dentro =
    target && diasConComida
      ? kcalPorDia.filter((x) => x.value <= target).length
      : 0;

  const proteinaPorDia: Point[] = kcalPorDia.map((x) => ({
    date: x.date,
    value: (porDia.get(x.date) ?? []).reduce(
      (a, m) => a + Number(m.total_protein_g),
      0,
    ),
  }));

  const aguaPorDia: Point[] = water.map((w) => ({
    date: w.local_date,
    value: w.glasses,
  }));
  const suenoPorDia: Point[] = sleep.map((s) => ({
    date: s.local_date,
    value: s.minutes / 60,
  }));
  const actPorDia = agrupar(
    activities.map((a) => ({ date: a.local_date, value: a.duration_minutes })),
  );

  const deltaPeso =
    weights.length >= 2
      ? Number(weights[weights.length - 1].weight_kg) -
        Number(weights[0].weight_kg)
      : null;

  const porMetrica = new Map<string, { local_date: string; value: number; unit: string }[]>();
  for (const m of measurements) {
    porMetrica.set(m.metric, [...(porMetrica.get(m.metric) ?? []), m]);
  }

  return (
    <main className="page">
      <p className="caption">
        <Link href="/">← Pacientes</Link>
      </p>

      <div
        className="row"
        style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}
      >
        <div>
          <h1>{p.patient_name || 'Sin nombre'}</h1>
          <p className="caption">
            {[
              p.birth_date ? `${edad(p.birth_date)} años` : null,
              p.height_cm ? `${Math.round(p.height_cm)} cm` : null,
              goal?.goal_type ? OBJETIVO[goal.goal_type] : null,
            ]
              .filter(Boolean)
              .join(' · ')}
          </p>
        </div>
        <RangePicker current={String(days)} />
      </div>

      {/* ── Resumen ──────────────────────────────────────────────────── */}
      <Section
        title="Resumen del período"
        hint={`Últimos ${days} días · del ${corto(from)} al ${corto(to)}`}
      >
        <StatRow>
          {p.share_meals && (
            <>
              <Stat
                label="Promedio diario"
                value={promedioKcal ? String(promedioKcal) : '—'}
                unit="kcal"
                caption={target ? `objetivo ${target}` : 'sin objetivo cargado'}
              />
              <Stat
                label="Días con comidas"
                value={`${diasConComida}`}
                unit={`de ${days}`}
                caption={
                  diasConComida < days
                    ? `${days - diasConComida} sin registrar`
                    : 'completo'
                }
              />
              {target !== null && target > 0 && (
                <Stat
                  label="Días dentro del objetivo"
                  value={`${dentro}`}
                  unit={`de ${diasConComida}`}
                />
              )}
            </>
          )}
          {p.share_body && (
            <Stat
              label="Variación de peso"
              value={
                deltaPeso === null
                  ? '—'
                  : `${deltaPeso > 0 ? '+' : ''}${deltaPeso.toFixed(1)}`
              }
              unit="kg"
              caption={
                weights.length
                  ? `último ${Number(weights[weights.length - 1].weight_kg).toFixed(1)} kg`
                  : 'sin registros'
              }
            />
          )}
          {p.share_wellbeing && (
            <>
              <Stat
                label="Actividad"
                value={`${activities.reduce((a, x) => a + x.duration_minutes, 0)}`}
                unit="min"
                caption={`${activities.length} ${activities.length === 1 ? 'sesión' : 'sesiones'}`}
              />
              <Stat
                label="Sueño promedio"
                value={
                  sleep.length
                    ? horas(
                        Math.round(
                          sleep.reduce((a, s) => a + s.minutes, 0) / sleep.length,
                        ),
                      )
                    : '—'
                }
              />
              <Stat
                label="Agua promedio"
                value={
                  water.length
                    ? (
                        water.reduce((a, w) => a + w.glasses, 0) / water.length
                      ).toFixed(1)
                    : '—'
                }
                unit="vasos"
              />
            </>
          )}
        </StatRow>
      </Section>

      {/* ── Comidas ──────────────────────────────────────────────────── */}
      {p.share_meals ? (
        <>
          <Section
            title="Calorías por día"
            hint="La línea punteada es el objetivo del día."
          >
            <div className="card">
              <CaloriesChart
                days={kcalPorDia.map((x) => ({ date: x.date, kcal: x.value }))}
                target={target}
              />
            </div>
          </Section>

          <Section
            title="Proteínas por día"
            hint="Es el macro que más cambia qué conviene ajustar."
          >
            <div className="card">
              <BarChart
                points={proteinaPorDia}
                unit="g"
                color="var(--chart-protein)"
                target={goal?.protein_g ?? null}
              />
            </div>
          </Section>
        </>
      ) : (
        <NoCompartido que="Las comidas" />
      )}

      {/* ── Cuerpo ───────────────────────────────────────────────────── */}
      {p.share_body ? (
        <>
          <Section
            title="Peso"
            hint="Los puntos son cada pesaje; la línea es la media móvil de 7 días, que es la que muestra la tendencia."
          >
            <div className="card">
              <WeightChart logs={weights} />
            </div>
          </Section>

          {porMetrica.size > 0 && (
            <Section
              title="Medidas corporales"
              hint="Perímetros y bioimpedancia. La bioimpedancia es una estimación indirecta: cambia con la hidratación y la hora del día."
            >
              <div className="grid">
                {[...porMetrica.entries()].map(([metric, serie]) => (
                  <div className="card" key={metric}>
                    <h3>{METRIC_LABEL[metric] ?? metric}</h3>
                    <div style={{ marginTop: 'var(--s3)' }}>
                      <BarChart
                        points={serie.map((s) => ({
                          date: s.local_date,
                          value: Number(s.value),
                        }))}
                        unit={serie[0].unit === 'pct' ? '%' : 'cm'}
                        color="var(--chart-weight)"
                        height={120}
                        decimals={1}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </Section>
          )}
        </>
      ) : (
        <NoCompartido que="El peso y las medidas" />
      )}

      {/* ── Hábitos ──────────────────────────────────────────────────── */}
      {p.share_wellbeing ? (
        <Section
          title="Actividad, agua y sueño"
          hint="Las calorías del ejercicio son una estimación por MET, no una medición."
        >
          <div className="grid">
            <div className="card">
              <h3>Minutos de actividad</h3>
              <div style={{ marginTop: 'var(--s3)' }}>
                <BarChart
                  points={actPorDia}
                  unit="min"
                  color="var(--chart-walking, var(--accent))"
                  height={130}
                />
              </div>
            </div>
            <div className="card">
              <h3>Agua</h3>
              <div style={{ marginTop: 'var(--s3)' }}>
                <BarChart
                  points={aguaPorDia}
                  unit="vasos"
                  color="var(--info)"
                  height={130}
                />
              </div>
            </div>
            <div className="card">
              <h3>Sueño</h3>
              <div style={{ marginTop: 'var(--s3)' }}>
                <BarChart
                  points={suenoPorDia}
                  unit="h"
                  color="var(--chart-weight)"
                  height={130}
                  decimals={1}
                />
              </div>
            </div>
          </div>
        </Section>
      ) : (
        <NoCompartido que="La actividad, el agua y el sueño" />
      )}

      {/* ── Día a día ────────────────────────────────────────────────── */}
      <Section
        title="Día a día"
        hint="Cada día con sus comidas por momento, los ítems de cada una y lo que se registró alrededor."
      >
        {!p.share_meals && !p.share_wellbeing && (
          <div className="card">
            <p className="muted">Nada compartido para mostrar acá.</p>
          </div>
        )}

        {(p.share_meals || p.share_wellbeing) &&
          [...fechas]
            .reverse()
            .filter(
              (d) =>
                porDia.has(d) ||
                activities.some((a) => a.local_date === d) ||
                water.some((w) => w.local_date === d) ||
                sleep.some((s) => s.local_date === d),
            )
            .map((d) => (
              <DayCard
                key={d}
                date={d}
                meals={porDia.get(d) ?? []}
                activities={activities.filter((a) => a.local_date === d)}
                water={water.find((w) => w.local_date === d)}
                sleep={sleep.find((s) => s.local_date === d)}
                targetKcal={target}
                photoUrls={photoUrls}
                sharePhotos={p.share_photos}
                shareWellbeing={p.share_wellbeing}
              />
            ))}

        {(p.share_meals || p.share_wellbeing) &&
          fechas.every(
            (d) =>
              !porDia.has(d) &&
              !activities.some((a) => a.local_date === d) &&
              !water.some((w) => w.local_date === d) &&
              !sleep.some((s) => s.local_date === d),
          ) && (
            <div className="card">
              <p className="muted">Sin registros en este período.</p>
            </div>
          )}
      </Section>
    </main>
  );
}

const OBJETIVO: Record<string, string> = {
  lose: 'Bajar de peso',
  maintain: 'Mantener',
  gain: 'Subir de peso',
};

function NoCompartido({ que }: { que: string }) {
  return (
    <Section title={que}>
      <div className="card">
        <p className="muted">
          No está compartido. Se prende desde la app, en Perfil → Mi
          nutricionista.
        </p>
      </div>
    </Section>
  );
}

/** Suma los valores que caen en el mismo día. */
function agrupar(points: Point[]): Point[] {
  const out = new Map<string, number>();
  for (const p of points) out.set(p.date, (out.get(p.date) ?? 0) + p.value);
  return [...out.entries()]
    .map(([date, value]) => ({ date, value }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

function rango(from: string, to: string): string[] {
  const out: string[] = [];
  const d = new Date(`${from}T00:00:00`);
  const end = new Date(`${to}T00:00:00`);
  while (d <= end) {
    out.push(d.toISOString().slice(0, 10));
    d.setDate(d.getDate() + 1);
  }
  return out;
}

function hoy(): string {
  return new Date().toISOString().slice(0, 10);
}

function hace(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().slice(0, 10);
}

function corto(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('es-AR', {
    day: 'numeric',
    month: 'short',
  });
}

function edad(birthDate: string): number {
  const n = new Date(birthDate);
  const h = new Date();
  let a = h.getFullYear() - n.getFullYear();
  const mes = h.getMonth() - n.getMonth();
  if (mes < 0 || (mes === 0 && h.getDate() < n.getDate())) a--;
  return a;
}
