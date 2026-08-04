'use client';

import Link from 'next/link';
import { usePathname, useSearchParams } from 'next/navigation';

/** El texto es lo corto que se lee, no los días exactos: "365 d" obliga a
 *  hacer la cuenta para saber que es un año. La etiqueta accesible sí dice el
 *  número, que es lo que hace falta para saber de qué período se habla. */
const OPCIONES = [
  { dias: 7, texto: '7 d', nombre: 'Últimos 7 días' },
  { dias: 30, texto: '30 d', nombre: 'Últimos 30 días' },
  { dias: 90, texto: '90 d', nombre: 'Últimos 90 días' },
  { dias: 365, texto: '1 año', nombre: 'Último año' },
];

/**
 * El período, como tres enlaces.
 *
 * El rango va en la URL y no en estado local: así un enlace a "los últimos 90
 * días de Ana" es un enlace, y volver atrás vuelve a lo que se estaba mirando.
 * Cambiarlo **sí** vuelve al servidor, porque cambia qué datos se piden — al
 * revés que las pestañas, que solo cambian qué se muestra de lo que ya vino.
 *
 * Son `<Link>` y no un `<select>` con `router.push` para que el clic del medio
 * abra otro período en una pestaña nueva, que es lo que uno hace cuando quiere
 * comparar. Y arrastran el resto de los parámetros —entre ellos la pestaña
 * abierta— para no devolver a "Resumen" a quien estaba mirando el día a día.
 */
export function RangePicker({ current }: { current: string }) {
  const pathname = usePathname();
  const params = useSearchParams();

  return (
    <div className="seg" role="group" aria-label="Período">
      {OPCIONES.map(({ dias, texto, nombre }) => {
        const next = new URLSearchParams(params.toString());
        next.set('dias', String(dias));
        return (
          <Link
            key={dias}
            href={`${pathname}?${next.toString()}`}
            // Sin `prefetch`, pasar el mouse por los cuatro pediría el paciente
            // entero cuatro veces para mostrar uno.
            prefetch={false}
            aria-current={String(dias) === current ? 'true' : undefined}
            aria-label={nombre}
            className="tnum"
          >
            {texto}
          </Link>
        );
      })}
    </div>
  );
}
