'use client';

import { useRouter, useSearchParams, usePathname } from 'next/navigation';

/**
 * El rango va en la URL y no en estado local: así un enlace a "los últimos 90
 * días de Ana" es un enlace, y volver atrás vuelve a lo que se estaba mirando.
 */
export function RangePicker({ current }: { current: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();

  return (
    <label className="row">
      <span className="caption">Período</span>
      <select
        value={current}
        onChange={(e) => {
          const next = new URLSearchParams(params.toString());
          next.set('dias', e.target.value);
          router.push(`${pathname}?${next.toString()}`);
        }}
      >
        <option value="7">7 días</option>
        <option value="30">30 días</option>
        <option value="90">90 días</option>
      </select>
    </label>
  );
}
