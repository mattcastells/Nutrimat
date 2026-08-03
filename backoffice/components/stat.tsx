/**
 * El número de arriba de una sección, con su unidad y su aclaración.
 *
 * No es un gráfico y no debería serlo: "promedio de 1.940 kcal" es un dato que
 * se lee de una vez, y dibujarlo como barra de una sola barra sería decorar un
 * número. La guía de visualización llama a esto una stat tile.
 */
export function Stat({
  label,
  value,
  unit,
  caption,
  tone,
}: {
  label: string;
  value: string;
  unit?: string;
  caption?: string;
  tone?: 'estimate' | 'muted';
}) {
  return (
    <div className="card" style={{ padding: 'var(--s4) var(--s5)' }}>
      <div className="caption">{label}</div>
      <div
        className="tnum"
        style={{
          fontSize: 24,
          marginTop: 2,
          color: tone === 'estimate' ? 'var(--caution)' : 'var(--text)',
        }}
      >
        {value}
        {unit && (
          <span
            className="muted"
            style={{ fontSize: 14, marginLeft: 4, fontVariantNumeric: 'normal' }}
          >
            {unit}
          </span>
        )}
      </div>
      {caption && (
        <div className="caption" style={{ marginTop: 2 }}>
          {caption}
        </div>
      )}
    </div>
  );
}

export function StatRow({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        display: 'grid',
        gap: 'var(--s3)',
        gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))',
      }}
    >
      {children}
    </div>
  );
}

/** Un encabezado de sección con su bajada, para que cada bloque diga qué es. */
export function Section({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section style={{ marginTop: 'var(--s8)' }}>
      <h2>{title}</h2>
      {hint && (
        <p className="caption" style={{ marginTop: 2, marginBottom: 'var(--s4)' }}>
          {hint}
        </p>
      )}
      {!hint && <div style={{ height: 'var(--s4)' }} />}
      {children}
    </section>
  );
}
