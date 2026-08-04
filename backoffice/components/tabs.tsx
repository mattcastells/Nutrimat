'use client';

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';

/** `useLayoutEffect` en el navegador y `useEffect` en el servidor.
 *
 *  La compensación de la cabecera tiene que quedar aplicada **antes** de que se
 *  pinte el cuadro: con `useEffect` a secas, el navegador alcanza a dibujar un
 *  cuadro con el documento más corto y recorta el scroll, que es un tironcito
 *  visible justo cuando uno está scrolleando. Y `useLayoutEffect` a secas avisa
 *  por consola en el render del servidor, donde no existe. */
const useEfectoDeLayout =
  typeof window === 'undefined' ? useEffect : useLayoutEffect;

export type Tab = {
  id: string;
  label: string;
  /** Marca la pestaña de una categoría que el paciente no comparte. */
  off?: boolean;
  content: ReactNode;
};

/**
 * La cabecera fija con las pestañas, y los paneles debajo.
 *
 * **Las pestañas no vuelven al servidor.** Los paneles llegan ya renderizados
 * —son Server Components pasados como `content`— y cambiar de pestaña solo
 * cambia cuál está visible. Si cada una fuera una navegación, moverse entre
 * "Comidas" y "Cuerpo" volvería a pedir las comidas, el peso, las medidas y a
 * firmar de nuevo las URLs de todas las fotos, para mostrar algo que ya
 * estaba en la página.
 *
 * La pestaña activa igual queda en la URL, con `replaceState`: así recargar
 * cae donde uno estaba y un enlace a "el día a día de Ana" es un enlace. Se usa
 * el History API nativo justamente porque no dispara la navegación de Next.
 *
 * Los paneles inactivos se ocultan con `hidden` en vez de desmontarse: un
 * `<details>` que alguien abrió sigue abierto al volver, y el navegador no
 * rearma un día entero cada vez que se cambia de pestaña.
 */
export function Tabs({
  header,
  tabs,
  initial,
  param = 't',
}: {
  header: ReactNode;
  tabs: Tab[];
  initial: string;
  param?: string;
}) {
  const known = tabs.some((t) => t.id === initial) ? initial : tabs[0].id;
  const [active, setActive] = useState(known);
  const [compact, setCompact] = useState(false);
  const sentinel = useRef<HTMLDivElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const cabecera = useRef<HTMLElement>(null);

  // Un centinela de 1 px arriba de todo en lugar de escuchar el scroll: el
  // observer avisa una vez cuando cruza, y no en cada píxel.
  useEffect(() => {
    const node = sentinel.current;
    if (!node) return;
    const io = new IntersectionObserver(
      ([entry]) => setCompact(!entry.isIntersecting),
      { threshold: 0 },
    );
    io.observe(node);
    return () => io.disconnect();
  }, []);

  /**
   * Cuánto se achica la cabecera al compactarse, para que el CSS lo devuelva.
   *
   * Sin esta compensación **la página se come el scroll**. La cabecera es
   * `sticky`, así que ocupa lugar en el flujo: al pasar a compacta perdía unos
   * 45 px de alto y el documento entero se acortaba lo mismo. En una pestaña
   * apenas más alta que la pantalla eso alcanzaba para que no quedara nada que
   * scrollear —medido: documento 619, pantalla 561, y al compactarse el máximo
   * de scroll pasaba de 58 px a 13—. Uno bajaba y la página no se movía.
   *
   * La compensación la hace el CSS (`.topbar.is-compact + .page`) y no un
   * `useLayoutEffect`, porque **tiene que pasar en el mismo cálculo de layout
   * que el cambio de clase**. Con un efecto, aunque sea de layout, el navegador
   * ya midió el documento más corto y ya recortó el scroll: devolverle el alto
   * un instante después no devuelve la posición.
   *
   * Acá solo se mide cuánto vale la diferencia. Se toma poniendo y sacando la
   * clase a mano dentro de un efecto de layout —invisible, porque no llega a
   * pintarse— en vez de restar una constante: la diferencia depende de si el
   * nombre y la línea de contexto entran en una línea o en dos.
   */
  useEfectoDeLayout(() => {
    const node = cabecera.current;
    if (!node) return;

    function medir() {
      if (!node) return;
      const estaba = node.classList.contains('is-compact');
      node.classList.remove('is-compact');
      const completa = node.offsetHeight;
      node.classList.add('is-compact');
      const chica = node.offsetHeight;
      node.classList.toggle('is-compact', estaba);
      document.documentElement.style.setProperty(
        '--topbar-delta',
        `${Math.max(0, completa - chica)}px`,
      );
    }

    medir();
    window.addEventListener('resize', medir);
    return () => window.removeEventListener('resize', medir);
  }, []);

  function select(id: string) {
    setActive(id);

    const url = new URL(window.location.href);
    if (id === tabs[0].id) url.searchParams.delete(param);
    else url.searchParams.set(param, id);
    window.history.replaceState(null, '', url);

    // Volver arriba: sin esto, entrar a "Cuerpo" desde el final del día a día
    // deja la pantalla en un panel más corto que el scroll, o sea en blanco.
    window.scrollTo({ top: 0 });
  }

  /** Flechas para moverse entre pestañas, que es lo que espera un `tablist`. */
  function onKeyDown(event: React.KeyboardEvent) {
    const delta =
      event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    if (delta === 0) return;
    event.preventDefault();

    const i = tabs.findIndex((t) => t.id === active);
    const next = tabs[(i + delta + tabs.length) % tabs.length];
    select(next.id);
    list.current
      ?.querySelector<HTMLButtonElement>(`#tab-${next.id}`)
      ?.focus();
  }

  return (
    <>
      <div ref={sentinel} aria-hidden style={{ height: 1 }} />

      <header
        ref={cabecera}
        className={`topbar${compact ? ' is-compact' : ''}`}
      >
        <div className="topbar-inner">
          {header}

          <div
            className="tabs"
            role="tablist"
            aria-label="Secciones"
            ref={list}
            onKeyDown={onKeyDown}
          >
            {tabs.map((t) => (
              <button
                key={t.id}
                id={`tab-${t.id}`}
                className="tab"
                role="tab"
                type="button"
                aria-selected={t.id === active}
                aria-controls={`panel-${t.id}`}
                tabIndex={t.id === active ? 0 : -1}
                onClick={() => select(t.id)}
              >
                {t.label}
                {t.off && (
                  <span
                    className="tab-off"
                    title="No está compartido"
                    aria-label="no está compartido"
                    role="img"
                  />
                )}
              </button>
            ))}
          </div>
        </div>
      </header>

      <main className="page">
        {tabs.map((t) => (
          <div
            key={t.id}
            id={`panel-${t.id}`}
            className="panel"
            role="tabpanel"
            aria-labelledby={`tab-${t.id}`}
            tabIndex={0}
            hidden={t.id !== active}
          >
            {t.content}
          </div>
        ))}
      </main>
    </>
  );
}
