'use client';

import { useState } from 'react';
import type { WeightLog } from '@/lib/queries';
import { conSigno, dec, diasEntre, fechaCorta } from '@/lib/format';
import { ticksEnRango, useChartWidth } from '@/lib/chart';

/**
 * Peso en el tiempo, con su media móvil.
 *
 * Una serie sola: no hay paleta categórica que validar y por eso no lleva
 * leyenda —el título ya la nombra—. Los puntos son el dato y la línea es la
 * tendencia, que es lo que se mira para decidir; el peso diario sube y baja por
 * agua y por la hora en que uno se pesa, y leer eso como progreso es el error
 * que la media móvil evita.
 *
 * **Los puntos van en su fecha, no repartidos parejo.** Con el eje por posición,
 * cinco pesajes de una semana y uno de un mes después se dibujaban a la misma
 * distancia entre sí, y la pendiente de la línea —que es todo lo que se mira
 * acá— salía inventada.
 */
export function WeightChart({
  logs,
  desde,
  hasta,
}: {
  logs: WeightLog[];
  desde?: string;
  hasta?: string;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const [box, ancho] = useChartWidth();

  if (logs.length < 2) {
    return (
      <p className="muted" style={{ margin: 0 }}>
        Con menos de dos registros no hay tendencia que mostrar.
      </p>
    );
  }

  const W = Math.max(ancho, 240);
  const H = 240;
  const PAD = { top: 16, right: 16, bottom: 28, left: 46 };
  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;

  const values = logs.map((l) => Number(l.weight_kg));
  const min = Math.min(...values);
  const max = Math.max(...values);
  // Un piso de rango evita que media docena de mediciones casi iguales se
  // dibujen como una montaña rusa: el eje mentiría sobre la magnitud.
  const span = Math.max(max - min, 1);
  const lo = min - span * 0.15;
  const hi = max + span * 0.15;

  const inicio = desde ?? logs[0].local_date;
  const fin = hasta ?? logs[logs.length - 1].local_date;
  const tramo = Math.max(diasEntre(inicio, fin), 1);

  const x = (i: number) =>
    PAD.left + (diasEntre(inicio, logs[i].local_date) / tramo) * innerW;
  const y = (v: number) => PAD.top + innerH - ((v - lo) / (hi - lo)) * innerH;

  // Media móvil de 7, hacia atrás: es la que usa la app.
  const trend = values.map((_, i) => {
    const from = Math.max(0, i - 6);
    const slice = values.slice(from, i + 1);
    return slice.reduce((a, b) => a + b, 0) / slice.length;
  });

  const trendPath = trend
    .map((v, i) => `${i === 0 ? 'M' : 'L'} ${x(i).toFixed(1)} ${y(v).toFixed(1)}`)
    .join(' ');

  const point = hover === null ? null : logs[hover];

  return (
    <div className="scroll-x chart" ref={box} style={{ position: 'relative' }}>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        width={W}
        height={H}
        style={{ display: 'block' }}
        role="img"
        aria-label={`Peso desde ${logs[0].local_date} hasta ${logs[logs.length - 1].local_date}`}
        onMouseLeave={() => setHover(null)}
      >
        {ticksEnRango(lo, hi).map((v) => (
          <g key={v}>
            <line
              x1={PAD.left}
              x2={W - PAD.right}
              y1={y(v)}
              y2={y(v)}
              stroke="var(--divider)"
              strokeWidth="1"
            />
            <text
              x={PAD.left - 8}
              y={y(v) + 4}
              textAnchor="end"
              fontSize="11"
              fill="var(--text-muted)"
              className="tnum"
            >
              {dec(v)}
            </text>
          </g>
        ))}

        <path
          d={trendPath}
          fill="none"
          stroke="var(--chart-trend)"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity="0.75"
        />

        {logs.map((l, i) => (
          <circle
            key={l.local_date}
            cx={x(i)}
            cy={y(Number(l.weight_kg))}
            r={hover === i ? 6 : 4}
            fill="var(--chart-weight)"
            stroke="var(--surface)"
            strokeWidth="2"
          />
        ))}

        {/* Las zonas de hover son más anchas que los puntos: apuntarle a un
            círculo de 4 px es una prueba de puntería, no una interacción. Con
            los puntos ya ubicados por fecha, cada zona llega hasta la mitad de
            camino al vecino en vez de medir todas lo mismo. */}
        {logs.map((l, i) => {
          const izq = i === 0 ? x(0) - 12 : (x(i - 1) + x(i)) / 2;
          const der =
            i === logs.length - 1 ? x(i) + 12 : (x(i) + x(i + 1)) / 2;
          return (
            <rect
              key={`hit-${l.local_date}`}
              x={izq}
              y={PAD.top}
              width={Math.max(der - izq, 6)}
              height={innerH}
              fill="transparent"
              onMouseEnter={() => setHover(i)}
            />
          );
        })}

        <text
          x={PAD.left}
          y={H - 8}
          fontSize="11"
          fill="var(--text-muted)"
          className="tnum"
        >
          {fechaCorta(inicio)}
        </text>
        <text
          x={W - PAD.right}
          y={H - 8}
          textAnchor="end"
          fontSize="11"
          fill="var(--text-muted)"
          className="tnum"
        >
          {fechaCorta(fin)}
        </text>
      </svg>

      {point && (
        <div className="chart-tip tnum">
          <div className="caption">{fechaCorta(point.local_date)}</div>
          <div style={{ fontSize: 17 }}>{dec(Number(point.weight_kg))} kg</div>
          {hover !== null && hover > 0 && (
            <div className="caption">
              {conSigno(
                Number(point.weight_kg) - Number(logs[0].weight_kg),
              )}{' '}
              kg desde el inicio
            </div>
          )}
        </div>
      )}
    </div>
  );
}
