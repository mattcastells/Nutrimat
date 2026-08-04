import {
  SLOT_LABEL,
  QUALITY_LABEL,
  esEstimacionIA,
  type Activity,
  type Meal,
  type SleepLog,
  type WaterLog,
} from '@/lib/queries';
import { fechaLarga, hora, horas, miles, num } from '@/lib/format';

const SLOT_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];

/**
 * Un día entero, que es la unidad con la que se revisa un seguimiento.
 *
 * **Nace cerrado**, y esa es la decisión de esta pantalla. Treinta días
 * abiertos son treinta tablas de seis columnas: para llegar al martes hay que
 * pasar por todo lo que se comió el miércoles. Cerrado, cada día es una línea
 * que dice lo que se pregunta primero —qué momentos registró, cuántas calorías,
 * cuánto se corrió del objetivo— y el detalle está a un clic.
 *
 * Cerrar también es lo que hace que la pantalla cargue liviana: las fotos son
 * `loading="lazy"` adentro de un `<details>` cerrado, así que el navegador no
 * baja veintiocho imágenes para mostrar una lista de fechas.
 *
 * Las comidas van agrupadas por momento y **en orden fijo** —desayuno, almuerzo,
 * cena, snacks— y no por hora de carga: alguien que anota la cena a la mañana
 * siguiente no debería reordenarle el día a quien lo lee. Un momento sin nada se
 * muestra igual, en gris: "no cenó" es información, y si la fila desaparece se
 * confunde con "no lo cargó".
 */
export function DayCard({
  date,
  meals,
  activities,
  water,
  sleep,
  targetKcal,
  photoUrls,
  sharePhotos,
  shareWellbeing,
  defaultOpen = false,
}: {
  date: string;
  meals: Meal[];
  activities: Activity[];
  water: WaterLog | undefined;
  sleep: SleepLog | undefined;
  targetKcal: number | null;
  photoUrls: Record<string, string>;
  sharePhotos: boolean;
  shareWellbeing: boolean;
  defaultOpen?: boolean;
}) {
  const total = meals.reduce((a, m) => a + m.total_kcal, 0);
  const p = meals.reduce((a, m) => a + Number(m.total_protein_g), 0);
  const c = meals.reduce((a, m) => a + Number(m.total_carbs_g), 0);
  const g = meals.reduce((a, m) => a + Number(m.total_fat_g), 0);
  const diff = targetKcal ? total - targetKcal : null;

  const fotos = meals.filter(
    (m) => sharePhotos && m.photo_path && photoUrls[m.photo_path],
  ).length;

  const resumen = meals.length
    ? [
        `P ${Math.round(p)} · C ${Math.round(c)} · G ${Math.round(g)} g`,
        `${meals.length} ${meals.length === 1 ? 'comida' : 'comidas'}`,
        fotos ? `${fotos} ${fotos === 1 ? 'foto' : 'fotos'}` : null,
      ]
        .filter(Boolean)
        .join(' · ')
    : 'Sin comidas registradas';

  return (
    <details className="card day" open={defaultOpen}>
      <summary>
        <Chev />

        <div className="day-title">
          <div className="day-date">{fechaLarga(date)}</div>
          <div className="caption tnum">{resumen}</div>
        </div>

        {/* Qué momentos tienen algo, sin abrir. Los cuatro están siempre: el
            que falta se ve apagado, no ausente. */}
        <div className="chips day-chips" aria-hidden>
          {SLOT_ORDER.map((slot) => {
            const hay = meals.some((m) => m.slot === slot);
            return (
              <span key={slot} className={hay ? 'chip chip--on' : 'chip'}>
                {SLOT_LABEL[slot]}
              </span>
            );
          })}
        </div>

        {/* Un día sin comidas no tiene total ni distancia al objetivo: va una
            raya. "0 kcal · −1.850 vs objetivo" en verde sería felicitar a
            alguien por no haber registrado, que es justo el número que no
            queremos inventar. La columna se queda igual —vacía se movería todo
            lo demás y las filas dejarían de alinearse—. */}
        <div className="day-kcal tnum">
          {meals.length === 0 ? (
            <span className="muted" style={{ fontSize: 17 }}>
              —
            </span>
          ) : (
            <>
              <span style={{ fontSize: 17 }}>{miles(total)}</span>
              <span className="muted"> kcal</span>
              {/* La distancia al objetivo no lleva verde de "bien".
                  Quedarse 700 kcal por debajo del objetivo se pintaba de
                  verde, y en una consulta eso no es un logro: es
                  sub-registro o una restricción, que es de lo que la
                  profesional tiene que enterarse. El único color es el
                  ámbar de haberse pasado, el mismo del gráfico de calorías,
                  y sigue siendo un dato y no una calificación. */}
              {diff !== null && (
                <div
                  className="caption"
                  style={diff > 0 ? { color: 'var(--caution)' } : undefined}
                >
                  {diff > 0 ? `+${miles(diff)}` : `−${miles(Math.abs(diff))}`}{' '}
                  vs objetivo
                </div>
              )}
            </>
          )}
        </div>
      </summary>

      <div className="day-body">
        {SLOT_ORDER.map((slot) => {
          const del = meals.filter((m) => m.slot === slot);
          return (
            <div className="slot" key={slot}>
              <div className="slot-head">
                <strong
                  style={{
                    fontWeight: 500,
                    color: del.length ? 'var(--text)' : 'var(--text-muted)',
                  }}
                >
                  {SLOT_LABEL[slot]}
                </strong>
                <span className="tnum caption">
                  {del.length
                    ? `${miles(del.reduce((a, m) => a + m.total_kcal, 0))} kcal`
                    : 'Sin registro'}
                </span>
              </div>

              {del.map((m) => (
                <MealRow
                  key={m.id}
                  meal={m}
                  photoUrls={photoUrls}
                  sharePhotos={sharePhotos}
                />
              ))}
            </div>
          );
        })}

        {shareWellbeing && (
          <div className="slot">
            <div className="slot-head">
              <strong style={{ fontWeight: 500 }}>Alrededor de las comidas</strong>
            </div>
            <div
              style={{
                marginTop: 'var(--s3)',
                display: 'grid',
                gap: 'var(--s3)',
                gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
              }}
            >
              <div>
                <div className="caption">Actividad</div>
                {activities.length === 0 ? (
                  <p className="caption muted" style={{ margin: 0 }}>
                    Sin registro
                  </p>
                ) : (
                  activities.map((a) => (
                    <div key={a.id} className="caption tnum">
                      {hora(a.started_at)} · {a.duration_minutes} min
                      {a.estimated_calories !== null && (
                        <span className="estimate">
                          {' '}
                          · ≈ {a.estimated_calories} kcal
                        </span>
                      )}
                    </div>
                  ))
                )}
              </div>

              <div>
                <div className="caption">Agua</div>
                <div className="caption tnum">
                  {water ? `${water.glasses} vasos` : 'Sin registro'}
                </div>
              </div>

              <div>
                <div className="caption">Sueño</div>
                <div className="caption tnum">
                  {sleep
                    ? `${horas(sleep.minutes)} · ${QUALITY_LABEL[sleep.quality ?? 'ok'] ?? ''}`
                    : 'Sin registro'}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </details>
  );
}

/**
 * Una comida: el nombre, la hora y el total; adentro, los ítems y la foto.
 *
 * La tabla de ítems es lo que hace pesado a un día —seis columnas por comida,
 * cuatro comidas— y casi nunca es lo primero que se busca. Con la comida
 * cerrada, el día abierto entra entero en una pantalla.
 */
function MealRow({
  meal,
  photoUrls,
  sharePhotos,
}: {
  meal: Meal;
  photoUrls: Record<string, string>;
  sharePhotos: boolean;
}) {
  const foto = sharePhotos && meal.photo_path ? photoUrls[meal.photo_path] : null;

  return (
    <details className="meal">
      <summary>
        <Chev />
        <span>{meal.name || 'Comida'}</span>
        <span className="caption tnum">{hora(meal.logged_at)}</span>
        {esEstimacionIA(meal) && (
          <span className="tag tag--ai">Estimado por IA</span>
        )}
        {foto && <Camara />}
        <span className="tnum meal-kcal">
          {miles(meal.total_kcal)}
          <span className="muted"> kcal</span>
        </span>
      </summary>

      <div className="meal-body">
        <div className="scroll-x">
          <table>
            <thead>
              <tr>
                <th>Ítem</th>
                <th style={{ textAlign: 'right' }}>Cantidad</th>
                <th style={{ textAlign: 'right' }}>kcal</th>
                <th style={{ textAlign: 'right' }}>P</th>
                <th style={{ textAlign: 'right' }}>C</th>
                <th style={{ textAlign: 'right' }}>G</th>
              </tr>
            </thead>
            <tbody>
              {meal.meal_items.map((it) => (
                <tr key={it.id}>
                  <td>
                    {it.name}
                    {it.ai_confidence !== null && it.ai_confidence < 0.5 && (
                      <span
                        className="caption estimate"
                        style={{ marginLeft: 6 }}
                      >
                        confianza baja
                      </span>
                    )}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {num(it.quantity)} {it.unit}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {it.kcal}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {num(it.protein_g)}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {num(it.carbs_g)}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {num(it.fat_g)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {foto && (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img
            src={foto}
            alt={`Foto de ${SLOT_LABEL[meal.slot] ?? meal.slot}`}
            loading="lazy"
            style={{
              marginTop: 'var(--s4)',
              maxWidth: 260,
              width: '100%',
              borderRadius: 'var(--radius-md)',
              display: 'block',
            }}
          />
        )}
      </div>
    </details>
  );
}

/** "Esta comida tiene foto", dibujado y no con un emoji: el emoji lo pinta cada
 *  sistema a su manera y mete un color que no es de la paleta en una fila que
 *  es toda gris. */
function Camara() {
  return (
    <svg
      width="13"
      height="13"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.3"
      className="muted"
      role="img"
      aria-label="con foto"
    >
      <title>Con foto</title>
      <path d="M1.8 5.2h2.6l1.1-1.6h4.9l1.1 1.6h2.7v7.2H1.8z" />
      <circle cx="8" cy="8.8" r="2.4" />
    </svg>
  );
}

/** La flecha del colapsable. Gira 90° cuando el `<details>` está abierto. */
export function Chev() {
  return (
    <svg
      className="chev"
      width="11"
      height="11"
      viewBox="0 0 10 10"
      aria-hidden="true"
    >
      <path
        d="M3.2 1.4 L6.9 5 L3.2 8.6"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
