'use client';

import { useEffect, useRef, useState } from 'react';

/**
 * Lo que comparten los gráficos: cuánto miden y dónde van las rayas del eje.
 */

/**
 * El ancho real de la caja, para dibujar el SVG a escala 1:1.
 *
 * Los gráficos dibujaban en un `viewBox` fijo de 720 px estirado con
 * `width="100%"`, y eso **escala también el texto**: la misma etiqueta de 11 px
 * salía de 16 px en una carta a todo lo ancho y de 7 px en una carta de dos
 * columnas, que es donde los ejes de "Cintura" y "Agua" se volvían ilegibles.
 * Midiendo la caja y dibujando a su ancho, un 11 son once píxeles en los dos
 * lados.
 *
 * El primer render del servidor usa el ancho de reserva y el navegador corrige
 * al montar. No hay salto de layout porque la altura del gráfico es fija.
 *
 * **El cero se ignora a propósito.** Los paneles de las pestañas que no están
 * activas se ocultan con `hidden`, y un elemento en `display: none` mide 0: sin
 * el guard, el gráfico de una pestaña que todavía no se abrió se dibujaría de
 * cero píxeles de ancho. El observer vuelve a disparar con la medida buena en
 * cuanto la pestaña se muestra —está verificado, no supuesto—, así que
 * quedarse con el ancho anterior hasta entonces es exactamente lo que hay que
 * hacer.
 */
export function useChartWidth(fallback = 720) {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(fallback);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;
    const ro = new ResizeObserver(([entry]) => {
      const next = Math.round(entry.contentRect.width);
      if (next > 0) setWidth(next);
    });
    ro.observe(node);
    return () => ro.disconnect();
  }, []);

  return [ref, width] as const;
}

/** Los pasos que se leen sin pensar, en cualquier potencia de diez. */
const PASOS = [0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5];

/**
 * Un eje desde cero que termina en un número redondo, sin regalar altura.
 *
 * Sin esto el tope era `max(datos) * 1.1` y las etiquetas salían `1.018` y
 * `2.035`: números que nadie eligió y que no ayudan a estimar una barra.
 *
 * De todos los pasos lindos se elige **el que menos aire deja arriba**, no el
 * primero que sirva: para un máximo de 2.050 kcal, tanto un paso de 500 como
 * uno de 1.000 dan un eje redondo, pero el de 1.000 termina en 3.000 y deja un
 * tercio del gráfico en blanco, con todas las barras aplastadas contra el piso.
 * El tope de intervalos es por legibilidad: seis rayas en un gráfico de 120 px
 * de alto se tocan entre sí.
 */
export function ejeLindo(
  max: number,
  maxIntervalos = 5,
): { max: number; ticks: number[] } {
  if (!(max > 0) || !Number.isFinite(max)) return { max: 1, ticks: [0, 1] };

  const magnitud = Math.pow(10, Math.floor(Math.log10(max)));
  let mejor: { paso: number; tope: number; n: number } | null = null;

  for (const m of PASOS) {
    const paso = m * magnitud;
    const n = Math.ceil(max / paso - 1e-9);
    if (n < 2 || n > maxIntervalos) continue;
    const tope = n * paso;
    if (!mejor || tope < mejor.tope - 1e-9) mejor = { paso, tope, n };
  }

  if (!mejor) {
    const tope = Math.ceil(max);
    return { max: tope, ticks: [0, tope] };
  }

  const ticks: number[] = [];
  for (let i = 0; i <= mejor.n; i++) {
    ticks.push(Number((i * mejor.paso).toFixed(6)));
  }
  return { max: mejor.tope, ticks };
}

/**
 * Rayas redondas **adentro** de un rango que no empieza en cero.
 *
 * Es para el peso y las medidas, donde el eje sí puede estar recortado porque
 * no se compara el largo de ninguna barra contra el cero. Repartir el rango en
 * tres partes iguales daba `78,5 · 77,1 · 75,6`, tres números que no significan
 * nada; acá salen 76, 77 y 78, que son los que uno tiene en la cabeza.
 */
export function ticksEnRango(
  lo: number,
  hi: number,
  maxTicks = 5,
  /** Con cuántos decimales se van a escribir las rayas.
   *
   *  El paso tiene que poder escribirse con esos decimales o las etiquetas
   *  mienten sobre la distancia: con pasos de 0,25 y un decimal, el eje del
   *  peso salía "77,5 · 77,8 · 78,0 · 78,3" —saltos de 0,3, 0,2 y 0,3 en rayas
   *  que están perfectamente equiespaciadas—. */
  decimales = 1,
): number[] {
  const span = hi - lo;
  if (!(span > 0) || !Number.isFinite(span)) return [lo];

  const magnitud = Math.pow(10, Math.floor(Math.log10(span)));
  const escala = Math.pow(10, decimales);

  // De menor a mayor: el primer paso que entra en el tope de rayas es el que
  // más marcas deja sin amontonarlas.
  for (const m of PASOS) {
    const paso = m * magnitud;
    if (Math.abs(Math.round(paso * escala) - paso * escala) > 1e-9) continue;

    const out: number[] = [];
    for (
      let v = Math.ceil(lo / paso - 1e-9) * paso;
      v <= hi + paso * 1e-9;
      v += paso
    ) {
      out.push(Number(v.toFixed(6)));
    }
    if (out.length >= 2 && out.length <= maxTicks) return out;
  }
  return [lo, hi];
}
