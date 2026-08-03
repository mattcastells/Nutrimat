'use client';

import { useState } from 'react';

export type Point = { date: string; value: number };

/**
 * Barras por día, una sola serie.
 *
 * Deliberadamente genérico y de una serie: agua, sueño, actividad y cada macro
 * usan este mismo componente. Una sola serie no necesita paleta categórica ni
 * leyenda —el título la nombra— y así ninguno de estos gráficos depende de
 * distinguir dos colores de marca, que es donde la paleta de la app no llega.
 *
 * Las barras nacen en cero. En una magnitud, un eje truncado convierte 1.900
 * contra 2.100 en el doble.
 */
export function BarChart({
  points,
  unit,
  color = 'var(--chart-intake)',
  target,
  targetLabel,
  format,
  height = 150,
}: {
  points: Point[];
  unit: string;
  color?: string;
  target?: number | null;
  targetLabel?: string;
  format?: (v: number) => string;
  height?: number;
}) {
  const [hover, setHover] = useState<number | null>(null);

  if (points.length === 0) {
    return <p className="muted">Sin registros en este período.</p>;
  }

  const fmt = format ?? ((v: number) => String(Math.round(v)));
  const W = 720;
  const H = height;
  const PAD = { top: 12, right: 12, bottom: 22, left: 44 };
  const innerW = W - PAD.left - PAD.right;
  const innerH = H - PAD.top - PAD.bottom;

  const max = Math.max(...points.map((p) => p.value), target ?? 0) * 1.1 || 1;
  const step = innerW / points.length;
  // 2 px de aire: sin el respiro, dos días seguidos se leen como un bloque.
  const barW = Math.max(step - 2, 1.5);
  const y = (v: number) => PAD.top + innerH - (v / max) * innerH;

  const point = hover === null ? null : points[hover];

  return (
    <div className="scroll-x" style={{ position: 'relative' }}>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        width="100%"
        style={{ minWidth: 380, display: 'block' }}
        role="img"
        aria-label={`Valores por día en ${unit}`}
        onMouseLeave={() => setHover(null)}
      >
        {[0, max].map((v, i) => (
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
              {fmt(v)}
            </text>
          </g>
        ))}

        {points.map((p, i) => (
          <rect
            key={p.date}
            x={PAD.left + i * step + 1}
            y={y(p.value)}
            width={barW}
            height={Math.max(innerH - (y(p.value) - PAD.top), 0)}
            rx="3"
            fill={color}
            opacity={hover === null || hover === i ? 1 : 0.5}
            onMouseEnter={() => setHover(i)}
          />
        ))}

        {target != null && target > 0 && (
          <line
            x1={PAD.left}
            x2={W - PAD.right}
            y1={y(target)}
            y2={y(target)}
            stroke="var(--chart-target)"
            strokeWidth="2"
            strokeDasharray="6 5"
          />
        )}

        <text
          x={PAD.left}
          y={H - 6}
          fontSize="10.5"
          fill="var(--text-muted)"
          className="tnum"
        >
          {corta(points[0].date)}
        </text>
        <text
          x={W - PAD.right}
          y={H - 6}
          textAnchor="end"
          fontSize="10.5"
          fill="var(--text-muted)"
          className="tnum"
        >
          {corta(points[points.length - 1].date)}
        </text>
      </svg>

      {point && (
        <div
          className="card tnum"
          style={{
            position: 'absolute',
            top: 0,
            right: 0,
            padding: 'var(--s2) var(--s3)',
            pointerEvents: 'none',
            boxShadow: 'var(--shadow-md)',
          }}
        >
          <div className="caption">{corta(point.date)}</div>
          <div>
            {fmt(point.value)} {unit}
          </div>
          {target != null && target > 0 && targetLabel && (
            <div className="caption">{targetLabel}</div>
          )}
        </div>
      )}
    </div>
  );
}

export function corta(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('es-AR', {
    day: 'numeric',
    month: 'short',
  });
}
