import Link from 'next/link';
import {
  METRIC_LABEL,
  QUALITY_LABEL,
  type Activity,
  type Goal,
  type Meal,
  type Measurement,
  type SleepLog,
  type WaterLog,
  type WeightLog,
} from '@/lib/queries';
import {
  conSigno,
  dec,
  fechaCorta,
  horas,
  miles,
  rangoDeFechas,
} from '@/lib/format';
import { WeightChart } from '@/components/weight-chart';
import { CaloriesChart } from '@/components/calories-chart';
import { BarChart, type Point } from '@/components/bar-chart';
import { DayCard } from '@/components/day-card';
import { Adherence } from '@/components/adherence';
import { SlotSplit } from '@/components/slot-split';
import { MacroSplit } from '@/components/macro-split';
import { PhotoGallery } from '@/components/photo-gallery';
import { MeasureCard } from '@/components/measure-card';
import { Stat, StatRow, Section } from '@/components/stat';
import { RangePicker } from '@/components/range-picker';
import { SignOut } from '@/components/sign-out';
import { Tabs, type Tab } from '@/components/tabs';

export type PatientProfile = {
  patient_id: string;
  patient_name: string | null;
  birth_date: string | null;
  height_cm: number | null;
  share_meals: boolean;
  share_photos: boolean;
  share_body: boolean;
  share_wellbeing: boolean;
};

export type PatientData = {
  patient: PatientProfile;
  days: number;
  from: string;
  to: string;
  meals: Meal[];
  weights: WeightLog[];
  water: WaterLog[];
  activities: Activity[];
  sleep: SleepLog[];
  measurements: Measurement[];
  goal: Goal | null;
  photoUrls: Record<string, string>;
};

/**
 * La ficha de un paciente, en cinco pestañas.
 *
 * Es una función pura de los datos: no consulta nada. Quien la usa —la página—
 * es quien pide, y por eso esta vista se puede renderizar con datos de ejemplo
 * para mirar el diseño sin una sesión. Lo que se mira ahí es el componente que
 * se despliega, no una maqueta parecida que se desincroniza al primer cambio.
 *
 * Las pestañas son las tres categorías que el paciente concede —comidas,
 * cuerpo, hábitos— más el resumen y el día a día. No es una división de
 * diseño: es la misma división con la que se dio el permiso, así que "esta
 * pestaña está apagada" y "esto no me lo compartieron" son la misma frase.
 */
export function PatientView({ data, tab }: { data: PatientData; tab?: string }) {
  const {
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
  } = data;

  const target = goal?.base_calorie_target ?? null;

  // Se recorren los días del período y no solo los que tienen algo: un hueco
  // es información —"no registró"— y una lista que salta del 3 al 7 lo esconde.
  const fechas = rangoDeFechas(from, to);
  const porDia = new Map<string, Meal[]>();
  for (const m of meals) {
    porDia.set(m.local_date, [...(porDia.get(m.local_date) ?? []), m]);
  }

  const kcalPorDia = new Map<string, number>();
  for (const [fecha, delDia] of porDia) {
    kcalPorDia.set(
      fecha,
      delDia.reduce((a, m) => a + m.total_kcal, 0),
    );
  }

  const serieKcal: Point[] = fechas
    .filter((d) => kcalPorDia.has(d))
    .map((d) => ({ date: d, value: kcalPorDia.get(d) ?? 0 }));

  const diasConComida = serieKcal.length;
  const promedioKcal = diasConComida
    ? Math.round(serieKcal.reduce((a, x) => a + x.value, 0) / diasConComida)
    : 0;
  const dentro =
    target && diasConComida
      ? serieKcal.filter((x) => x.value <= target).length
      : 0;

  const proteinaPorDia: Point[] = serieKcal.map((x) => ({
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

  const ultimoPeso = weights.length
    ? Number(weights[weights.length - 1].weight_kg)
    : null;
  const deltaPeso =
    weights.length >= 2 ? ultimoPeso! - Number(weights[0].weight_kg) : null;

  // El IMC sale de dos datos que ya estaban en la ficha y no se cruzaban. Es
  // grueso —no distingue músculo de grasa— pero es el número con el que se
  // habla en una consulta, y calcularlo a mano mirando la pantalla es trabajo
  // que la pantalla puede hacer.
  const indice =
    ultimoPeso && p.height_cm ? ultimoPeso / Math.pow(p.height_cm / 100, 2) : null;

  const porMetrica = new Map<string, Measurement[]>();
  for (const m of measurements) {
    porMetrica.set(m.metric, [...(porMetrica.get(m.metric) ?? []), m]);
  }

  const diasConAlgo = [...fechas]
    .reverse()
    .filter(
      (d) =>
        porDia.has(d) ||
        activities.some((a) => a.local_date === d) ||
        water.some((w) => w.local_date === d) ||
        sleep.some((s) => s.local_date === d),
    );

  const apagadas = [
    !p.share_meals && 'las comidas',
    !p.share_photos && 'las fotos',
    !p.share_body && 'el peso y las medidas',
    !p.share_wellbeing && 'la actividad, el agua y el sueño',
  ].filter(Boolean) as string[];

  const header = (
    <div className="topbar-id">
      <div style={{ minWidth: 0 }}>
        <p className="topbar-back caption">
          <Link href="/">← Pacientes</Link>
        </p>
        <h1>{p.patient_name || 'Sin nombre'}</h1>
        <p className="topbar-sub caption">
          {[
            p.birth_date ? `${edad(p.birth_date)} años` : null,
            p.height_cm ? `${Math.round(p.height_cm)} cm` : null,
            goal?.goal_type ? OBJETIVO[goal.goal_type] : null,
            target ? `objetivo ${miles(target)} kcal` : null,
          ]
            .filter(Boolean)
            .join(' · ')}
        </p>
      </div>

      <div className="row" style={{ flex: 'none' }}>
        <RangePicker current={String(days)} />
        <SignOut />
      </div>
    </div>
  );

  /* ── Resumen ────────────────────────────────────────────────────────── */
  const resumen = (
    <>
      <Section
        title="Resumen del período"
        hint={`Últimos ${days} días · del ${fechaCorta(from)} al ${fechaCorta(to)}`}
      >
        <StatRow>
          {p.share_meals && (
            <>
              <Stat
                label="Promedio diario"
                value={promedioKcal ? miles(promedioKcal) : '—'}
                unit="kcal"
                caption={
                  target ? `objetivo ${miles(target)}` : 'sin objetivo cargado'
                }
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
                  caption={
                    diasConComida
                      ? `${Math.round((dentro / diasConComida) * 100)} % de los registrados`
                      : undefined
                  }
                />
              )}
            </>
          )}
          {p.share_body && (
            <>
              <Stat
                label="Variación de peso"
                value={deltaPeso === null ? '—' : conSigno(deltaPeso)}
                unit="kg"
                caption={
                  ultimoPeso !== null
                    ? `último ${dec(ultimoPeso)} kg`
                    : 'sin registros'
                }
              />
              <Stat
                label="IMC"
                value={indice === null ? '—' : dec(indice)}
                caption={
                  indice === null
                    ? p.height_cm
                      ? 'sin peso cargado'
                      : 'falta la altura'
                    : categoriaIMC(indice)
                }
              />
            </>
          )}
          {p.share_wellbeing && (
            <>
              <Stat
                label="Actividad"
                value={miles(
                  activities.reduce((a, x) => a + x.duration_minutes, 0),
                )}
                unit="min"
                caption={`${activities.length} ${activities.length === 1 ? 'sesión' : 'sesiones'}`}
              />
              <Stat
                label="Sueño promedio"
                value={
                  sleep.length
                    ? horas(
                        Math.round(
                          sleep.reduce((a, s) => a + s.minutes, 0) /
                            sleep.length,
                        ),
                      )
                    : '—'
                }
                caption={`${sleep.length} ${sleep.length === 1 ? 'noche' : 'noches'} registradas`}
              />
              <Stat
                label="Agua promedio"
                value={
                  water.length
                    ? dec(
                        water.reduce((a, w) => a + w.glasses, 0) / water.length,
                      )
                    : '—'
                }
                unit="vasos"
                caption={`${water.length} ${water.length === 1 ? 'día' : 'días'} registrados`}
              />
            </>
          )}
        </StatRow>
      </Section>

      {/* En 7 días el calendario serían dos columnas de cuadraditos, que es
          menos claro que la ficha de arriba: "5 de 7 · 2 sin registrar" ya lo
          dice. Aparece cuando hay suficiente período como para ver una forma. */}
      {p.share_meals && days > 7 && (
        <Section
          title="Registro"
          hint="Qué días quedaron cargados. Un promedio alto sobre seis días no es lo mismo que sobre treinta."
        >
          <Adherence fechas={fechas} kcalPorDia={kcalPorDia} />
        </Section>
      )}

      {/* Las dos curvas que se miran primero, sin cambiar de pestaña. El
          detalle —macros, reparto, medidas— sigue estando en la suya: acá van
          las dos que contestan "¿cómo viene?" de un vistazo. */}
      {(p.share_meals || p.share_body) && (
        <Section
          title="Cómo viene"
          hint="Lo mismo, con más detalle, está en Comidas y en Cuerpo."
        >
          <div className="grid grid--auto">
            {p.share_meals && (
              <div className="card">
                <h3>Calorías por día</h3>
                <div style={{ marginTop: 'var(--s3)' }}>
                  <CaloriesChart
                    days={serieKcal.map((x) => ({
                      date: x.date,
                      kcal: x.value,
                    }))}
                    target={target}
                    desde={from}
                    hasta={to}
                  />
                </div>
              </div>
            )}
            {p.share_body && (
              <div className="card">
                <h3>Peso</h3>
                <div style={{ marginTop: 'var(--s3)' }}>
                  <WeightChart logs={weights} desde={from} hasta={to} />
                </div>
              </div>
            )}
          </div>
        </Section>
      )}

      {apagadas.length > 0 && (
        <Section title="Lo que no está compartido">
          <div className="card">
            <p className="muted" style={{ margin: 0 }}>
              No {apagadas.length === 1 ? 'está compartida' : 'están compartidas'}{' '}
              {enumerar(apagadas)}. Se prende desde la app, en Perfil → Mi
              nutricionista, y no hace falta volver a dar el código.
            </p>
          </div>
        </Section>
      )}
    </>
  );

  /* ── Comidas ────────────────────────────────────────────────────────── */
  const comidas = !p.share_meals ? (
    <NoCompartido que="Las comidas" />
  ) : (
    <>
      <Section
        title="Calorías por día"
        hint="La línea punteada es el objetivo. El día en ámbar es el que lo pasó."
      >
        <div className="card">
          <CaloriesChart
            days={serieKcal.map((x) => ({ date: x.date, kcal: x.value }))}
            target={target}
            desde={from}
            hasta={to}
          />
        </div>
      </Section>

      <Section
        title="Cómo se compone el día"
        hint={`Promedios sobre los ${diasConComida} días con comidas cargadas.`}
      >
        <div className="grid grid--auto">
          <div>
            <div className="section-header" style={{ marginTop: 0 }}>
              Macros
            </div>
            <MacroSplit
              meals={meals}
              diasConComida={diasConComida}
              goal={goal}
            />
          </div>
          <div>
            <div className="section-header" style={{ marginTop: 0 }}>
              Momento del día
            </div>
            <SlotSplit meals={meals} diasConComida={diasConComida} />
          </div>
        </div>
      </Section>

      <Section
        title="Proteínas por día"
        hint="El promedio esconde la variación: es el macro donde un día flojo se compensa mal con el siguiente."
      >
        <div className="card">
          <BarChart
            points={proteinaPorDia}
            unit="g"
            desde={from}
            hasta={to}
            color="var(--chart-protein)"
            target={goal?.protein_g ?? null}
            targetLabel={
              goal?.protein_g ? `objetivo ${miles(goal.protein_g)} g` : undefined
            }
            height={180}
          />
        </div>
      </Section>
    </>
  );

  /* ── Fotos ──────────────────────────────────────────────────────────── */

  // Se filtra acá, del lado del servidor: mandarle al navegador las comidas sin
  // foto para que las descarte sería pagar el peso de un año de tablas de
  // ítems para no dibujar ninguna.
  const conFoto = p.share_photos
    ? meals.filter((m) => m.photo_path && photoUrls[m.photo_path])
    : [];

  const fotos = !p.share_photos ? (
    <NoCompartido que="Las fotos" />
  ) : !p.share_meals ? (
    <Section title="Fotos">
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Las fotos vienen con las comidas, y las comidas no están compartidas.
          Se prende desde la app, en Perfil → Mi nutricionista.
        </p>
      </div>
    </Section>
  ) : (
    <Section
      title="Fotos de las comidas"
      hint={
        conFoto.length
          ? `${conFoto.length} ${conFoto.length === 1 ? 'foto' : 'fotos'} en el período, de la más reciente a la más vieja. Tocá una para ver qué se estimó.`
          : 'Las fotos que se sacaron al cargar cada comida.'
      }
    >
      <PhotoGallery meals={conFoto} photoUrls={photoUrls} />
    </Section>
  );

  /* ── Cuerpo ─────────────────────────────────────────────────────────── */
  const cuerpo = !p.share_body ? (
    <NoCompartido que="El peso y las medidas" />
  ) : (
    <>
      <Section
        title="Dónde está hoy"
        hint={`Último registro del período · ${weights.length} ${weights.length === 1 ? 'pesaje' : 'pesajes'}.`}
      >
        <StatRow>
          <Stat
            label="Peso"
            value={ultimoPeso === null ? '—' : dec(ultimoPeso)}
            unit="kg"
            caption={
              weights.length
                ? fechaCorta(weights[weights.length - 1].local_date)
                : 'sin registros'
            }
          />
          <Stat
            label="Variación en el período"
            value={deltaPeso === null ? '—' : conSigno(deltaPeso)}
            unit="kg"
            caption={
              weights.length >= 2
                ? `desde ${dec(Number(weights[0].weight_kg))} kg`
                : 'hace falta más de un pesaje'
            }
          />
          <Stat
            label="IMC"
            value={indice === null ? '—' : dec(indice)}
            caption={
              indice === null
                ? p.height_cm
                  ? 'sin peso cargado'
                  : 'falta la altura en el perfil'
                : categoriaIMC(indice)
            }
          />
          <Stat
            label="Altura"
            value={p.height_cm ? `${Math.round(p.height_cm)}` : '—'}
            unit="cm"
            caption="del perfil"
          />
        </StatRow>
      </Section>

      <Section
        title="Peso"
        hint="Los puntos son cada pesaje; la línea es la media móvil de 7 días, que es la que muestra la tendencia."
      >
        <div className="card">
          <WeightChart logs={weights} desde={from} hasta={to} />
        </div>
      </Section>

      <Section
        title="Medidas corporales"
        hint="Perímetros y bioimpedancia. La bioimpedancia es una estimación indirecta: cambia con la hidratación y la hora del día."
      >
        {porMetrica.size === 0 ? (
          <div className="card">
            <p className="muted" style={{ margin: 0 }}>
              Sin medidas cargadas en este período.
            </p>
          </div>
        ) : (
          <div className="grid grid--3">
            {[...porMetrica.entries()].map(([metric, serie]) => (
              <MeasureCard
                key={metric}
                title={METRIC_LABEL[metric] ?? metric}
                unit={serie[0].unit === 'pct' ? '%' : 'cm'}
                desde={from}
                hasta={to}
                points={serie.map((s) => ({
                  date: s.local_date,
                  value: Number(s.value),
                }))}
              />
            ))}
          </div>
        )}
      </Section>
    </>
  );

  /* ── Hábitos ────────────────────────────────────────────────────────── */
  const habitos = !p.share_wellbeing ? (
    <NoCompartido que="La actividad, el agua y el sueño" />
  ) : (
    <Section
      title="Actividad, agua y sueño"
      hint="Las calorías del ejercicio son una estimación por MET, no una medición."
    >
      <div className="grid grid--3">
        <div className="card habito">
          <h3>Actividad</h3>
          <p className="caption">
            {actPorDia.length} de {days} días con movimiento
          </p>
          <BarChart
            points={actPorDia}
            unit="min"
            desde={from}
            hasta={to}
            color="var(--chart-walking)"
            height={150}
          />
          <dl className="habito-pie">
            <div>
              <dt className="caption">Sesiones</dt>
              <dd className="tnum">{activities.length}</dd>
            </div>
            <div>
              <dt className="caption">Total</dt>
              <dd className="tnum">
                {miles(activities.reduce((a, x) => a + x.duration_minutes, 0))}{' '}
                min
              </dd>
            </div>
            <div>
              <dt className="caption">Gasto estimado</dt>
              {/* En ámbar y con el "≈", como en la app: una estimación por MET
                  no se presenta con la misma cara que una medición. */}
              <dd className="tnum estimate">
                ≈{' '}
                {miles(
                  activities.reduce((a, x) => a + (x.estimated_calories ?? 0), 0),
                )}{' '}
                kcal
              </dd>
            </div>
          </dl>
        </div>

        <div className="card habito">
          <h3>Agua</h3>
          <p className="caption">
            {water.length
              ? `${dec(water.reduce((a, w) => a + w.glasses, 0) / water.length)} vasos por día`
              : 'sin registros'}
          </p>
          <BarChart
            points={aguaPorDia}
            unit="vasos"
            desde={from}
            hasta={to}
            color="var(--info)"
            height={150}
          />
          <dl className="habito-pie">
            <div>
              <dt className="caption">Días registrados</dt>
              <dd className="tnum">
                {water.length} de {days}
              </dd>
            </div>
            <div>
              <dt className="caption">Llegó a 8 vasos</dt>
              <dd className="tnum">
                {water.filter((w) => w.glasses >= 8).length} días
              </dd>
            </div>
          </dl>
        </div>

        <div className="card habito">
          <h3>Sueño</h3>
          <p className="caption">
            {sleep.length
              ? `${horas(Math.round(sleep.reduce((a, s) => a + s.minutes, 0) / sleep.length))} por noche`
              : 'sin registros'}
          </p>
          <BarChart
            points={suenoPorDia}
            unit="h"
            desde={from}
            hasta={to}
            color="var(--chart-weight)"
            height={150}
            decimals={1}
          />
          {/* La calidad se guardaba y no se mostraba en ningún resumen: siete
              horas de sueño malo y siete de sueño bueno son dos cosas
              distintas, y era el único dato del que solo se veía la duración. */}
          {sleep.length > 0 && (
            <div className="habito-pie">
              <div style={{ width: '100%' }}>
                <div className="caption">Cómo lo calificó</div>
                <div className="chips" style={{ marginTop: 'var(--s2)' }}>
                  {calidades(sleep).map(([q, n]) => (
                    <span key={q} className="chip chip--on tnum">
                      {QUALITY_LABEL[q] ?? q} · {n}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </Section>
  );

  /* ── Día a día ──────────────────────────────────────────────────────── */
  const diario = (
    <Section
      title="Día a día"
      hint="Cada día empieza cerrado: la fila dice qué momentos registró y cuánto sumó. El detalle de cada comida se abre aparte."
    >
      {!p.share_meals && !p.share_wellbeing && (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>
            Nada compartido para mostrar acá.
          </p>
        </div>
      )}

      {(p.share_meals || p.share_wellbeing) && diasConAlgo.length === 0 && (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>
            Sin registros en este período.
          </p>
        </div>
      )}

      {/* El período de un año son 365 días, y cada día trae adentro sus
          comidas con la tabla de ítems entera: aunque nazcan cerrados, el HTML
          se manda igual y la página pasaría de unos cientos de kilobytes a
          varios megas para mostrar una lista de fechas. Se corta en 120 y se
          dice, que es mejor que una pantalla que tarda diez segundos o una que
          esconde el corte. Para el año están las otras pestañas, que resumen. */}
      {diasConAlgo.length > TOPE_DIARIO && (
        <div className="card" style={{ marginBottom: 'var(--s3)' }}>
          <p className="muted" style={{ margin: 0 }}>
            Se muestran los {TOPE_DIARIO} días más recientes de los{' '}
            {diasConAlgo.length} con registros. El período entero sigue contado
            en el resumen y en los gráficos; para ver más atrás, achicá el
            período o mirá las fotos.
          </p>
        </div>
      )}

      {diasConAlgo.slice(0, TOPE_DIARIO).map((d, i) => (
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
          // El más reciente abierto: es el que se mira al entrar, y deja ver
          // de una que el día se abre sin tener que descubrir el triángulo.
          defaultOpen={i === 0}
        />
      ))}
    </Section>
  );

  const tabs: Tab[] = [
    { id: 'resumen', label: 'Resumen', content: resumen },
    { id: 'comidas', label: 'Comidas', off: !p.share_meals, content: comidas },
    { id: 'fotos', label: 'Fotos', off: !p.share_photos, content: fotos },
    { id: 'cuerpo', label: 'Cuerpo', off: !p.share_body, content: cuerpo },
    {
      id: 'habitos',
      label: 'Hábitos',
      off: !p.share_wellbeing,
      content: habitos,
    },
    { id: 'diario', label: 'Día a día', content: diario },
  ];

  return <Tabs header={header} tabs={tabs} initial={tab ?? 'resumen'} />;
}

/** Cuántos días dibuja el "día a día" como máximo. Ver el comentario de arriba:
 *  el corte es por peso del HTML, no por gusto. */
const TOPE_DIARIO = 120;

const OBJETIVO: Record<string, string> = {
  lose: 'Bajar de peso',
  maintain: 'Mantener',
  gain: 'Subir de peso',
};

/** Las categorías de la OMS, con el nombre con el que se habla en consulta.
 *
 *  Va como aclaración del número y no como color: el IMC no distingue músculo
 *  de grasa, y pintar de rojo un 26 de alguien que entrena sería un diagnóstico
 *  que esta pantalla no está en condiciones de dar. */
function categoriaIMC(v: number): string {
  if (v < 18.5) return 'bajo peso';
  if (v < 25) return 'normal';
  if (v < 30) return 'sobrepeso';
  if (v < 35) return 'obesidad grado I';
  if (v < 40) return 'obesidad grado II';
  return 'obesidad grado III';
}

function NoCompartido({ que }: { que: string }) {
  return (
    <Section title={que}>
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          No está compartido. Se prende desde la app, en Perfil → Mi
          nutricionista.
        </p>
      </div>
    </Section>
  );
}

/** "a, b y c" — con la "y" del final, que es como se lee en castellano. */
function enumerar(items: string[]): string {
  if (items.length === 1) return items[0];
  return `${items.slice(0, -1).join(', ')} y ${items[items.length - 1]}`;
}

/** Cuántas noches de cada calidad, de la mejor a la peor.
 *
 *  El orden es el de la escala y no el de la cuenta: una lista ordenada por
 *  frecuencia cambia de orden entre pacientes y entre períodos, y entonces hay
 *  que leer las etiquetas para comparar dos fichas. */
const ESCALA_SUENO = ['great', 'good', 'ok', 'poor', 'bad'];

function calidades(sleep: SleepLog[]): [string, number][] {
  const cuenta = new Map<string, number>();
  for (const s of sleep) {
    const q = s.quality ?? 'ok';
    cuenta.set(q, (cuenta.get(q) ?? 0) + 1);
  }
  return ESCALA_SUENO.filter((q) => cuenta.has(q)).map((q) => [
    q,
    cuenta.get(q)!,
  ]);
}

/** Suma los valores que caen en el mismo día. */
function agrupar(points: Point[]): Point[] {
  const out = new Map<string, number>();
  for (const p of points) out.set(p.date, (out.get(p.date) ?? 0) + p.value);
  return [...out.entries()]
    .map(([date, value]) => ({ date, value }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

export function edad(birthDate: string): number {
  const n = new Date(birthDate);
  const h = new Date();
  let a = h.getFullYear() - n.getFullYear();
  const mes = h.getMonth() - n.getMonth();
  if (mes < 0 || (mes === 0 && h.getDate() < n.getDate())) a--;
  return a;
}
