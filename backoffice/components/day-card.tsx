import {
  SLOT_LABEL,
  QUALITY_LABEL,
  type Activity,
  type Meal,
  type SleepLog,
  type WaterLog,
} from '@/lib/queries';

const SLOT_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];

/**
 * Un día entero, que es la unidad con la que se revisa un seguimiento.
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
}) {
  const total = meals.reduce((a, m) => a + m.total_kcal, 0);
  const p = meals.reduce((a, m) => a + Number(m.total_protein_g), 0);
  const c = meals.reduce((a, m) => a + Number(m.total_carbs_g), 0);
  const g = meals.reduce((a, m) => a + Number(m.total_fat_g), 0);
  const diff = targetKcal ? total - targetKcal : null;

  return (
    <div className="card" style={{ marginBottom: 'var(--s4)' }}>
      <div
        className="row"
        style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}
      >
        <h3 style={{ textTransform: 'capitalize' }}>{largo(date)}</h3>
        <div className="tnum" style={{ textAlign: 'right' }}>
          <span style={{ fontSize: 18 }}>{total}</span>
          <span className="muted"> kcal</span>
          {diff !== null && (
            <div
              className="caption"
              style={{ color: diff > 0 ? 'var(--danger)' : 'var(--success)' }}
            >
              {diff > 0 ? `+${diff}` : diff} vs objetivo
            </div>
          )}
        </div>
      </div>

      <div className="row tnum caption" style={{ marginTop: 2, gap: 'var(--s4)' }}>
        <span>P {Math.round(p)} g</span>
        <span>C {Math.round(c)} g</span>
        <span>G {Math.round(g)} g</span>
      </div>

      {SLOT_ORDER.map((slot) => {
        const del = meals.filter((m) => m.slot === slot);
        return (
          <div key={slot} style={{ marginTop: 'var(--s5)' }}>
            <hr className="divider" />
            <div
              className="row"
              style={{
                justifyContent: 'space-between',
                marginTop: 'var(--s3)',
              }}
            >
              <strong style={{ color: del.length ? 'var(--text)' : 'var(--text-muted)' }}>
                {SLOT_LABEL[slot]}
              </strong>
              {del.length > 0 && (
                <span className="tnum caption">
                  {del.reduce((a, m) => a + m.total_kcal, 0)} kcal
                </span>
              )}
            </div>

            {del.length === 0 && (
              <p className="caption" style={{ marginTop: 2 }}>
                Sin registro
              </p>
            )}

            {del.map((m) => (
              <div key={m.id} style={{ marginTop: 'var(--s3)' }}>
                <div className="row" style={{ flexWrap: 'wrap' }}>
                  <span>{m.name || 'Comida'}</span>
                  <span className="caption tnum">{hora(m.logged_at)}</span>
                  {esIA(m) && <span className="tag tag--ai">Estimado por IA</span>}
                </div>

                <div className="scroll-x" style={{ marginTop: 'var(--s2)' }}>
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

                {m.photo_path && sharePhotos && photoUrls[m.photo_path] && (
                  /* eslint-disable-next-line @next/next/no-img-element */
                  <img
                    src={photoUrls[m.photo_path]}
                    alt={`Foto de ${SLOT_LABEL[m.slot] ?? m.slot}`}
                    loading="lazy"
                    style={{
                      marginTop: 'var(--s3)',
                      maxWidth: 240,
                      width: '100%',
                      borderRadius: 'var(--radius-md)',
                      display: 'block',
                    }}
                  />
                )}
              </div>
            ))}
          </div>
        );
      })}

      {shareWellbeing && (
        <>
          <hr className="divider" style={{ marginTop: 'var(--s5)' }} />
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
                <p className="caption muted">Sin registro</p>
              ) : (
                activities.map((a) => (
                  <div key={a.id} className="caption tnum">
                    {hora(a.started_at)} · {a.duration_minutes} min
                    {a.estimated_calories !== null && (
                      <span className="estimate"> · ≈ {a.estimated_calories} kcal</span>
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
        </>
      )}
    </div>
  );
}

function esIA(m: Meal): boolean {
  return m.source === 'ai_photo' || m.source === 'ai_text';
}

function num(v: number): string {
  const n = Number(v);
  return Number.isInteger(n) ? String(n) : n.toFixed(1).replace('.', ',');
}

export function horas(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

function hora(iso: string): string {
  return new Date(iso).toLocaleTimeString('es-AR', {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function largo(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('es-AR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
}
