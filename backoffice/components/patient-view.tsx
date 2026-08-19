import Link from 'next/link';
import {
  METRIC_LABEL,
  QUALITY_LABEL,
  type Activity,
  type AlcoholLog,
  type CareNote,
  type DayMarker,
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
  num,
  rangoDeFechas,
} from '@/lib/format';
import { notaDeRecorte, type Ventana } from '@/lib/tracking';
import { DayContext } from '@/components/day-context';
import { Notes } from '@/components/notes';
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
  /** El primer día del que hay algo cargado. Lo calcula `public.tracking_since`. */
  tracking_since: string | null;
};

export type PatientData = {
  patient: PatientProfile;
  days: number;
  from: string;
  to: string;
  /** El período efectivo, ya calculado en la página. Ver `lib/tracking.ts`. */
  ventana: Ventana;
  meals: Meal[];
  weights: WeightLog[];
  water: WaterLog[];
  activities: Activity[];
  sleep: SleepLog[];
  measurements: Measurement[];
  markers: DayMarker[];
  alcohol: AlcoholLog[];
  notes: CareNote[];
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
    ventana,
    meals,
    weights,
    water,
    activities,
    sleep,
    measurements,
    markers,
    alcohol,
    notes,
    goal,
    photoUrls,
  } = data;

  const target = goal?.base_calorie_target ?? null;

  // ⚠️ Dos listas de fechas, y la diferencia importa.
  //
  // `fechas` es el **calendario**: el eje X de los gráficos sale de acá y
  // arranca en `from` siempre, porque recortarlo movería las barras de lugar y
  // el gráfico contradiría al calendario de adherencia de al lado.
  //
  // `ventana.fechas` es lo que **se cuenta**: todo denominador, racha, hueco y
  // porcentaje sale de ahí. Alguien que empezó el 18 registró 13 de 13 días, no
  // 13 de 30. Ver `docs/contexto-diario.md`.
  const fechas = rangoDeFechas(from, to);
  const diasEfectivos = ventana.dias;
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


  /* ── El contexto del día ───────────────────────────────────────────────
     Se indexa una sola vez y lo usan el día a día, los gráficos y el resumen.
     Con un `.filter()` adentro de cada fila, un año de historial recorre la
     lista entera trescientas sesenta y cinco veces. */
  const marcasPorDia = new Map<string, DayMarker[]>();
  for (const m of markers) {
    marcasPorDia.set(m.local_date, [
      ...(marcasPorDia.get(m.local_date) ?? []),
      m,
    ]);
  }

  const alcoholPorDia = new Map<string, AlcoholLog[]>();
  for (const a of alcohol) {
    alcoholPorDia.set(a.local_date, [
      ...(alcoholPorDia.get(a.local_date) ?? []),
      a,
    ]);
  }

  const notasPorDia = new Map<string, CareNote[]>();
  for (const n of notes) {
    if (!n.local_date) continue;
    notasPorDia.set(n.local_date, [
      ...(notasPorDia.get(n.local_date) ?? []),
      n,
    ]);
  }

  const enfermos = markers.filter((m) => m.kind === 'sick');
  const descansos = markers.filter((m) => m.kind === 'rest');

  const ubePorDia = new Map<string, number>();
  for (const a of alcohol) {
    ubePorDia.set(a.local_date, (ubePorDia.get(a.local_date) ?? 0) + a.std_drinks);
  }
  const diasConAlcohol = ubePorDia.size;
  const ubeTotal = [...ubePorDia.values()].reduce((acc, v) => acc + v, 0);
  const kcalAlcohol = alcohol.reduce((acc, a) => acc + a.kcal, 0);

  // Las semanas del período, para poner las UBE contra el umbral semanal —que
  // es como está escrito en las guías— y no contra un total que crece con el
  // período elegido y no se puede comparar con nada.
  const semanas = diasEfectivos > 0 ? diasEfectivos / 7 : 0;
  const ubePorSemana = semanas > 0 ? ubeTotal / semanas : 0;
  const diasConAlgo = [...fechas]
    .reverse()
    .filter(
      (d) =>
        porDia.has(d) ||
        activities.some((a) => a.local_date === d) ||
        water.some((w) => w.local_date === d) ||
        sleep.some((s) => s.local_date === d) ||
        // Un día marcado como enfermedad, o con alcohol, **es** un día con
        // algo: si no entrara acá, el día que la persona estuvo en cama y no
        // registró nada desaparecería del día a día, que es justo el día que
        // hay que poder abrir para entender la semana.
        marcasPorDia.has(d) ||
        alcoholPorDia.has(d),
    );


  const apagadas = [
    !p.share_meals && 'las comidas',
    !p.share_photos && 'las fotos',
    !p.share_body && 'el peso y las medidas',
    !p.share_wellbeing && 'la actividad, el agua, el sueño y el contexto del día',
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
        {/* El recorte se **dice**, no solo se aplica: "13 de 13" sin la
            aclaración parece un período de trece días elegido a mano, y la
            profesional necesita saber que pidió treinta. */}
        {notaDeRecorte(ventana) && (
          <div className="card" style={{ marginBottom: 'var(--s3)' }}>
            <p className="muted" style={{ margin: 0 }}>
              {notaDeRecorte(ventana)}
            </p>
          </div>
        )}
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
              {/* El denominador es la ventana efectiva y no `days`: alguien
                  que empezó el 18 registró 13 de 13, no 13 de 30. Los otros 17
                  no son huecos, son días sin la app. */}
              <Stat
                label="Días con comidas"
                value={`${diasConComida}`}
                unit={diasEfectivos > 0 ? `de ${diasEfectivos}` : undefined}
                caption={
                  diasEfectivos === 0
                    ? 'sin registros todavía'
                    : diasConComida < diasEfectivos
                      ? `${diasEfectivos - diasConComida} sin registrar`
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
          <Adherence fechas={fechas} kcalPorDia={kcalPorDia} ventana={ventana} />
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

      {/* ── Qué más pasó en el período ──────────────────────────────────
          Va al final del resumen y **solo si hay algo**: es lo que explica a
          los números de arriba, no una métrica más. Una sección permanente que
          diga "0 días de enfermedad · 0 tragos" convierte en ruido de todas las
          semanas lo que tiene que saltar la semana que pasó algo.
          Ver `docs/contexto-diario.md`. */}
      {p.share_wellbeing &&
        (enfermos.length > 0 || diasConAlcohol > 0 || descansos.length > 0) && (
        <Section
          title="Qué más pasó"
          hint="No cambia ningún número de arriba: los promedios y la adherencia se calculan igual. Está para poder leerlos."
        >
          <StatRow>
            {enfermos.length > 0 && (
              <Stat
                label="Días de enfermedad"
                value={`${enfermos.length}`}
                unit={diasEfectivos > 0 ? `de ${diasEfectivos}` : undefined}
                caption={resumenEnfermedad(enfermos)}
              />
            )}
            {/* El descanso planificado y el día sin actividad se ven igual en
                el gráfico, y no son lo mismo: uno es el plan y el otro es lo
                que no pasó. */}
            {descansos.length > 0 && (
              <Stat
                label="Descansos planificados"
                value={`${descansos.length}`}
                caption="marcados como descanso, no como día sin moverse"
              />
            )}
            {diasConAlcohol > 0 && (
              <>
                <Stat
                  label="Días con alcohol"
                  value={`${diasConAlcohol}`}
                  unit={diasEfectivos > 0 ? `de ${diasEfectivos}` : undefined}
                  caption={`${num(ubeTotal)} tragos en el período`}
                />
                {/* Por semana y no el total: el umbral de las guías está escrito
                    por semana, y un total crece con el período elegido y no se
                    puede comparar con nada. Sin semáforo: la pantalla muestra
                    distancias, no notas. */}
                <Stat
                  label="Tragos por semana"
                  value={num(ubePorSemana)}
                  caption="referencia de bajo riesgo: hasta 9–14 según sexo"
                />
                <Stat
                  label="Calorías del alcohol"
                  value={miles(kcalAlcohol)}
                  unit="kcal"
                  caption="aparte de las comidas, no suman al promedio"
                />
              </>
            )}
          </StatRow>
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
    <NoCompartido que="La actividad, el agua, el sueño y el contexto del día" />
  ) : (
    <Section
      title="Actividad, agua, sueño y contexto"
      hint="Las calorías del ejercicio son una estimación por MET, no una medición."
    >
      <div className="grid grid--3">
        <div className="card habito">
          <h3>Actividad</h3>
          <p className="caption">
            {actPorDia.length} de {diasEfectivos} días con movimiento
          </p>
          {/* Acá es donde el contexto vale más: el hueco de actividad es el que
              más se parece a abandono y el que más seguido tiene una
              explicación. Las bandas van al pie del gráfico, no como color de
              la barra: un día de enfermedad con 20 minutos de caminata sigue
              siendo 20 minutos. Ver `docs/contexto-diario.md`. */}
          <BarChart
            points={actPorDia}
            unit="min"
            desde={from}
            hasta={to}
            color="var(--chart-walking)"
            height={150}
            sickDays={enfermos.map((m) => m.local_date)}
            drinkDays={[...ubePorDia.keys()]}
          />
          {(enfermos.length > 0 || diasConAlcohol > 0) && (
            <p className="caption chart-legend">
              {enfermos.length > 0 && (
                <span>
                  <i className="swatch swatch--sick" /> día de enfermedad
                </span>
              )}
              {diasConAlcohol > 0 && (
                <span>
                  <i className="swatch swatch--drink" /> con alcohol
                </span>
              )}
            </p>
          )}
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
                {water.length} de {diasEfectivos}
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
          // El contexto entra en la fila que ya existe y no en una sección
          // aparte: "sin registros" y "estuvo enfermo" se leen juntos o no se
          // leen. Ver `docs/contexto-diario.md`.
          markers={marcasPorDia.get(d) ?? []}
          alcohol={alcoholPorDia.get(d) ?? []}
          notes={notasPorDia.get(d) ?? []}
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
    // Las notas van **después** del día a día y no entre las cuatro del medio:
    // esas cuatro son exactamente las cuatro categorías del permiso, y esa
    // correspondencia —"esta pestaña está apagada" y "esto no me lo
    // compartieron" son la misma frase— es lo que hace legible la pantalla.
    // Meter acá una que no es del paciente la rompería.
    {
      id: 'notas',
      label: notes.length ? `Notas · ${notes.length}` : 'Notas',
      content: (
        <Section
          title="Tus notas"
          hint="Lo que observaste, lo que acordaron, qué mirar la próxima vez. Son tuyas: el paciente no las ve."
        >
          <Notes
            patientId={p.patient_id}
            notes={notes}
            patientName={p.patient_name}
          />
        </Section>
      ),
    },
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

/** "2 seguidos · 12 y 13 de agosto" — de qué días se está hablando.
 *
 *  El número solo ("2 días") no alcanza: dos días sueltos en un mes y dos días
 *  pegados son dos cosas distintas, y la segunda es la que explica el hueco de
 *  la semana. */
function resumenEnfermedad(marcas: DayMarker[]): string {
  const fechas = marcas.map((m) => m.local_date).sort();
  const partes = fechas.slice(0, 3).map((f) => fechaCorta(f));
  const resto = fechas.length - 3;
  return resto > 0 ? `${partes.join(', ')} +${resto}` : partes.join(', ');
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
