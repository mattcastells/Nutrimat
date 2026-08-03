'use client';

import { useState } from 'react';
import type { WeightLog } from '@/lib/queries';

/**
 * Peso en el tiempo, con su media móvil.
 *
 * Una serie sola: no hay paleta categórica que validar y por eso no lleva
 * leyenda —el título ya la nombra—. Los puntos son el dato y la línea es la
 * tendencia, que es lo que se mira para decidir; el peso diario sube y baja por
 * agua y por la hora en que uno se pesa, y leer eso como progreso es el error
 * que la media móvil evita.
 */
export function WeightChart({ logs }: { logs: WeightLog[] }) {
  const [hover, setHover] = useState<number | null>(null);

  if (logs.length < 2) {
    return (
      <p className="muted">
        Con menos de dos registros no hay tendencia que mostrar.
      </p>
    );
  }

  const W = 720;
  const H = 240;
  const PAD = { top: 16, right: 16, bottom: 28, left: 44 };
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

  const x = (i: number) =>
    PAD.left + (logs.length === 1 ? innerW / 2 : (i / (logs.length - 1)) * innerW);
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
    <div className="scroll-x" style={{ position: 'relative' }}>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        width="100%"
        style={{ minWidth: 420, display: 'block' }}
        role="img"
        aria-label={`Peso desde ${logs[0].local_date} hasta ${logs[logs.length - 1].local_date}`}
        onMouseLeave={() => setHover(null)}
      >
        {[lo, (lo + hi) / 2, hi].map((v, i) => (
          <g key={i}>
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
              {v.toFixed(1)}
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
            círculo de 4 px es una prueba de puntería, no una interacción. */}
        {logs.map((l, i) => (
          <rect
            key={`hit-${l.local_date}`}
            x={x(i) - innerW / logs.length / 2}
            y={PAD.top}
            width={innerW / logs.length}
            height={innerH}
            fill="transparent"
            onMouseEnter={() => setHover(i)}
          />
        ))}

        <text
          x={PAD.left}
          y={H - 8}
          fontSize="11"
          fill="var(--text-muted)"
          className="tnum"
        >
          {fecha(logs[0].local_date)}
        </text>
        <text
          x={W - PAD.right}
          y={H - 8}
          textAnchor="end"
          fontSize="11"
          fill="var(--text-muted)"
          className="tnum"
        >
          {fecha(logs[logs.length - 1].local_date)}
        </text>
      </svg>

      {point && (
        <div
          className="card tnum"
          style={{
            position: 'absolute',
            top: 0,
            right: 0,
            padding: 'var(--s3) var(--s4)',
            pointerEvents: 'none',
            boxShadow: 'var(--shadow-md)',
          }}
        >
          <div className="caption">{fecha(point.local_date)}</div>
          <div style={{ fontSize: 17 }}>{Number(point.weight_kg).toFixed(1)} kg</div>
        </div>
      )}
    </div>
  );
}

function fecha(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('es-AR', {
    day: 'numeric',
    month: 'short',
  });
}
