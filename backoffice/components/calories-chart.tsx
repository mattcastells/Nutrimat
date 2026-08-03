'use client';

import { useState } from 'react';

export type DayKcal = { date: string; kcal: number };

/**
 * Calorías por día contra el objetivo.
 *
 * Una sola serie de barras y una línea de referencia. **No** es un gráfico de
 * dos ejes: el objetivo está en las mismas kcal que las barras, así que
 * comparte la escala y se lee como lo que es, una raya que se cruza o no.
 *
 * Las barras nacen en el cero y no en el mínimo del rango: en una magnitud, un
 * eje truncado convierte 1.900 contra 2.100 en el doble.
 */
export function CaloriesChart({
  days,
  target,
}: {
  days: DayKcal[];
  target: number | null;
}) {
  const [hover, setHover] = useState<number | null>(null);

  if (days.length === 0) {
    return <p className="muted">Sin comidas cargadas en este período.</p>;
  }

  const W = 720;
  const H = 240;
  const PAD = { top: 16, right: 16, bottom: 28, left: 48 };
  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;

  const max = Math.max(...days.map((d) => d.kcal), target ?? 0) * 1.1 || 1;
  const step = innerW / days.length;
  // 2 px de aire entre barras: sin el respiro, dos días seguidos se leen como
  // un bloque.
  const barW = Math.max(step - 2, 2);

  const y = (v: number) => PAD.top + innerH - (v / max) * innerH;
  const point = hover === null ? null : days[hover];

  return (
    <div className="scroll-x" style={{ position: 'relative' }}>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        width="100%"
        style={{ minWidth: 420, display: 'block' }}
        role="img"
        aria-label="Calorías consumidas por día"
        onMouseLeave={() => setHover(null)}
      >
        {[0, max / 2, max].map((v, i) => (
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
              {Math.round(v)}
            </text>
          </g>
        ))}

        {days.map((d, i) => {
          const h = Math.max(innerH - (y(d.kcal) - PAD.top), 0);
          return (
            <rect
              key={d.date}
              x={PAD.left + i * step + 1}
              y={y(d.kcal)}
              width={barW}
              height={h}
              rx="4"
              fill="var(--chart-intake)"
              opacity={hover === null || hover === i ? 1 : 0.55}
              onMouseEnter={() => setHover(i)}
            />
          );
        })}

        {target !== null && target > 0 && (
          <>
            <line
              x1={PAD.left}
              x2={W - PAD.right}
              y1={y(target)}
              y2={y(target)}
              stroke="var(--chart-target)"
              strokeWidth="2"
              strokeDasharray="6 5"
            />
            <text
              x={W - PAD.right}
              y={y(target) - 6}
              textAnchor="end"
              fontSize="11"
              fill="var(--text-muted)"
              className="tnum"
            >
              objetivo {target}
            </text>
          </>
        )}
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
          <div className="caption">{fecha(point.date)}</div>
          <div style={{ fontSize: 17 }}>{point.kcal} kcal</div>
          {target !== null && target > 0 && (
            <div className="caption">
              {point.kcal > target
                ? `${point.kcal - target} por encima`
                : `${target - point.kcal} por debajo`}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function fecha(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('es-AR', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });
}
