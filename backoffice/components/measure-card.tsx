'use client';

import { conSigno, dec, diasEntre, fechaCorta } from '@/lib/format';
import { useChartWidth } from '@/lib/chart';

export type MeasurePoint = { date: string; value: number };

/**
 * Una medida corporal en el período: cuánto mide hoy y cuánto se movió.
 *
 * **No es un gráfico de barras, y esa es la corrección.** Un perímetro es una
 * posición en una escala, no una magnitud que se acumule: la barra desde cero
 * de una cintura de 88 cm y la de una de 85 cm miden 97 % lo mismo, así que el
 * gráfico dibujaba tres bloques idénticos y el cambio —los 3 cm, que es todo
 * lo que se quería ver— quedaba adentro del error de lectura.
 *
 * Acá el número es el dato y la línea es la forma. La línea **sí** puede tener
 * el eje recortado, porque no se está comparando el largo de nada contra cero:
 * es una tendencia, y la aclaración de arriba dice de dónde a dónde va.
 *
 * La variación va en el color del texto y no en verde o rojo: que la cintura
 * baje es bueno en un plan de descenso y malo en uno de ganancia de masa, y la
 * pantalla no sabe cuál es cuál.
 */
export function MeasureCard({
  title,
  unit,
  points,
  desde,
  hasta,
}: {
  title: string;
  unit: string;
  points: MeasurePoint[];
  /** Los extremos del período: la línea se dibuja sobre el tiempo elegido
   *  arriba y no sobre la lista de mediciones, que repartidas parejo darían una
   *  pendiente que no es la que pasó. */
  desde?: string;
  hasta?: string;
}) {
  const [box, ancho] = useChartWidth(320);

  const ultimo = points[points.length - 1];
  const delta = points.length >= 2 ? ultimo.value - points[0].value : null;

  const W = Math.max(ancho, 160);
  const H = 56;
  const PAD = 6;

  const valores = points.map((p) => p.value);
  const min = Math.min(...valores);
  const max = Math.max(...valores);
  // Un piso de rango: media docena de mediciones casi iguales dibujadas a
  // escala completa serían una montaña rusa, y el eje mentiría sobre cuánto
  // cambió en realidad.
  const span = Math.max(max - min, Math.max(max * 0.02, 0.5));
  const lo = min - span * 0.25;
  const hi = max + span * 0.25;

  const inicio = desde ?? points[0].date;
  const fin = hasta ?? ultimo.date;
  const tramo = Math.max(diasEntre(inicio, fin), 1);

  const x = (i: number) =>
    PAD + (diasEntre(inicio, points[i].date) / tramo) * (W - PAD * 2);
  const y = (v: number) => PAD + (H - PAD * 2) * (1 - (v - lo) / (hi - lo));

  const path = points
    .map((p, i) => `${i === 0 ? 'M' : 'L'} ${x(i).toFixed(1)} ${y(p.value).toFixed(1)}`)
    .join(' ');

  return (
    <div className="card measure">
      <div className="measure-head">
        <h3>{title}</h3>
        {delta !== null && (
          <span className="tnum caption">
            {conSigno(delta)} {unit} en el período
          </span>
        )}
      </div>

      <div className="measure-value tnum">
        {dec(ultimo.value)}
        <span className="muted measure-unit">{unit}</span>
      </div>

      <div ref={box} className="measure-spark">
        {points.length >= 2 && (
          <svg
            viewBox={`0 0 ${W} ${H}`}
            width={W}
            height={H}
            style={{ display: 'block' }}
            role="img"
            aria-label={`${title}: de ${dec(points[0].value)} a ${dec(ultimo.value)} ${unit}`}
          >
            <path
              d={path}
              fill="none"
              stroke="var(--chart-weight)"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
            {points.map((p, i) => (
              <circle
                key={p.date}
                cx={x(i)}
                cy={y(p.value)}
                r={i === points.length - 1 ? 4 : 2.5}
                fill="var(--chart-weight)"
                stroke="var(--surface)"
                strokeWidth={i === points.length - 1 ? 2 : 0}
              >
                <title>{`${fechaCorta(p.date)} · ${dec(p.value)} ${unit}`}</title>
              </circle>
            ))}
          </svg>
        )}
      </div>

      <div className="measure-foot caption tnum">
        <span>{fechaCorta(inicio)}</span>
        <span>
          {points.length} {points.length === 1 ? 'medición' : 'mediciones'}
        </span>
        <span>{fechaCorta(fin)}</span>
      </div>
    </div>
  );
}
