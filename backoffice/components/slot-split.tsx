import { SLOT_LABEL, type Meal } from '@/lib/queries';
import { miles } from '@/lib/format';

const SLOT_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];

/**
 * Cómo se reparten las calorías entre los cuatro momentos del día.
 *
 * Es una pregunta que el gráfico de calorías por día no contesta: dos personas
 * con el mismo promedio comen distinto si una hace tres comidas y la otra pone
 * la mitad del día en la cena. Cuatro barras con su nombre al lado, una sola
 * tinta: no hay tres colores de marca que distinguir.
 */
export function SlotSplit({
  meals,
  diasConComida,
}: {
  meals: Meal[];
  diasConComida: number;
}) {
  const total = meals.reduce((a, m) => a + m.total_kcal, 0);

  if (!total || !diasConComida) {
    return (
      <div className="card">
        <p className="muted" style={{ margin: 0 }}>
          Sin comidas cargadas en este período.
        </p>
      </div>
    );
  }

  return (
    <div className="card">
      {SLOT_ORDER.map((slot) => {
        const kcal = meals
          .filter((m) => m.slot === slot)
          .reduce((a, m) => a + m.total_kcal, 0);
        const pct = Math.round((kcal / total) * 100);

        return (
          <div className="split-row" key={slot}>
            <span>{SLOT_LABEL[slot]}</span>
            <div className="split-track" aria-hidden>
              <div className="split-fill" style={{ width: `${pct}%` }} />
            </div>
            <span className="tnum caption">
              {pct} % · {miles(kcal / diasConComida)} kcal/día
            </span>
          </div>
        );
      })}

      <p className="caption" style={{ marginTop: 'var(--s5)', marginBottom: 0 }}>
        El promedio es sobre los {diasConComida} días con comidas cargadas, no
        sobre el período: dividir por los días en blanco bajaría todo por igual
        y diría que come menos, cuando lo que pasó es que no registró.
      </p>
    </div>
  );
}
