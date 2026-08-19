import { diaDeSemana, fechaLarga, miles } from '@/lib/format';
import type { Ventana } from '@/lib/tracking';

const LETRAS = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];

/**
 * El período entero, un cuadradito por día.
 *
 * Responde la primera pregunta de una consulta —"¿está registrando?"— que un
 * promedio no responde: 1.900 kcal de promedio son otra cosa si vienen de
 * veintiocho días o de seis. Y es el único lugar donde los huecos se ven,
 * porque el gráfico de calorías por día **saltea** los días sin registro a
 * propósito: una barra en cero diría que comió cero, que no es lo que pasó.
 *
 * Las filas son los días de la semana, así que "los fines de semana no
 * registra" se ve como una franja y no hay que ir a buscarlo. Al costado va lo
 * mismo contado en números, que es lo que se anota en la historia clínica: la
 * franja se ve, pero "nueve días seguidos" hay que contarlo con el dedo.
 *
 * Una sola tinta y la intensidad como magnitud. No hay verde de "bien" ni rojo
 * de "mal": el color es cuánto, no si estuvo bien. El día sin registro no es un
 * violeta clarito —eso lo pondría en la misma escala, como si fuera "comió
 * poco"— sino un gris de otra familia, que es otra categoría.
 */
export function Adherence({
  fechas,
  kcalPorDia,
  ventana,
}: {
  /** El calendario completo del período: es lo que se **dibuja**. */
  fechas: string[];
  kcalPorDia: Map<string, number>;
  /** El período efectivo: es lo que se **cuenta**. Ver `lib/tracking.ts`. */
  ventana: Ventana;
}) {
  const valores = [...kcalPorDia.values()];
  const max = valores.length ? Math.max(...valores) : 0;

  // ⚠️ Dos listas, y confundirlas es el bug que este componente tenía.
  //
  // Se dibujan **todos** los días del período —el calendario es el calendario,
  // y un mes que empieza el jueves tiene que verse empezando el jueves—, pero
  // se cuentan solo los que la persona podía registrar. Alguien que empezó el
  // 18 tenía diecisiete cuadrados grises antes de su primer día, una racha rota
  // que nunca existió y un 4 % "entre semana".
  //
  // Los días anteriores se dibujan **fuera de la escala**: ni violetas ni del
  // gris de "no registró", porque no son ninguna de las dos cosas.
  // Ver `docs/contexto-diario.md`.
  const contadas = ventana.fechas;

  // La primera columna arranca en el día de semana que caiga: sin los huecos
  // de adelante, las filas dejan de ser lunes, martes, miércoles.
  const huecos = diaDeSemana(fechas[0]);
  const semanas = Math.ceil((huecos + fechas.length) / 7);

  // Treinta días son cinco columnas y noventa son catorce: con un tamaño fijo
  // uno de los dos queda mal, o estampilla o desbordado. El cuadrado apunta a
  // unos 420 px de ancho y se planta en 34, que es donde deja de parecer un
  // calendario y pasa a ser una grilla de botones.
  const cell = Math.min(34, Math.max(13, Math.floor(420 / semanas) - 3));

  const registrado = (f: string) => kcalPorDia.has(f);

  let rachaActual = 0;
  let rachaMax = 0;
  let huecoMax = 0;
  let huecoCorrido = 0;
  for (const f of contadas) {
    if (registrado(f)) {
      rachaActual += 1;
      rachaMax = Math.max(rachaMax, rachaActual);
      huecoCorrido = 0;
    } else {
      huecoCorrido += 1;
      huecoMax = Math.max(huecoMax, huecoCorrido);
      rachaActual = 0;
    }
  }

  const finesDeSemana = contadas.filter((f) => diaDeSemana(f) >= 5);
  const finesRegistrados = finesDeSemana.filter(registrado).length;
  const semana = contadas.filter((f) => diaDeSemana(f) < 5);
  const semanaRegistrados = semana.filter(registrado).length;

  // `—` y no "0 %" cuando no hay días de esa clase en el período efectivo:
  // alguien que empezó un lunes y mira una semana no tuvo ningún fin de semana
  // todavía, y "0 %" ahí se lee como que no registró el sábado.
  const pct = (parte: number, total: number) =>
    total ? `${Math.round((parte / total) * 100)} %` : '—';

  return (
    <div
      className="card cal-card"
      style={{ '--cell': `${cell}px` } as React.CSSProperties}
    >
      <div className="cal-layout">
        <div className="row" style={{ alignItems: 'flex-start' }}>
          <div className="cal-days" aria-hidden>
            {LETRAS.map((l, i) => (
              <span key={i}>{l}</span>
            ))}
          </div>

          <div className="scroll-x" style={{ paddingBottom: 2 }}>
            <div className="cal">
              {Array.from({ length: huecos }, (_, i) => (
                <span key={`hueco-${i}`} style={{ width: 'var(--cell)' }} />
              ))}

              {fechas.map((f) => {
                const kcal = kcalPorDia.get(f);
                // Anterior al primer registro de la cuenta: no es "no registró"
                // sino "todavía no existía", y por eso sale de la escala en vez
                // de pintarse del gris del día vacío.
                const antes = !ventana.vacia && f < ventana.desdeEfectivo;
                return (
                  <span
                    key={f}
                    className="cal-cell"
                    data-on={antes ? 'na' : kcal === undefined ? '0' : '1'}
                    style={
                      antes || kcal === undefined || !max
                        ? undefined
                        : {
                            // Se mezcla el color en vez de bajarle la opacidad:
                            // un violeta al 20 % sobre la carta queda del gris
                            // del día vacío, y ahí las dos cosas se confunden.
                            // El piso del 40 % es para que un día de 400 kcal se
                            // lea como un día con registro.
                            background: `color-mix(in srgb, var(--chart-intake) ${
                              40 + Math.round(60 * (kcal / max))
                            }%, var(--surface-raised))`,
                          }
                    }
                    title={
                      antes
                        ? `${fechaLarga(f)} · antes del primer registro`
                        : kcal === undefined
                          ? `${fechaLarga(f)} · sin registro`
                          : `${fechaLarga(f)} · ${miles(kcal)} kcal`
                    }
                  />
                );
              })}
            </div>
          </div>
        </div>

        <p className="caption cal-legend">
          Cada cuadrado es un día, de lunes a domingo. El gris es un día sin
          comidas cargadas; cuanto más violeta, más calorías registradas.
          {ventana.empezoDespues &&
            ' Los días vacíos del principio son anteriores al primer registro: no cuentan como huecos.'}
        </p>

        <dl className="cal-facts">
          <Dato
            termino="Racha más larga"
            valor={`${rachaMax} ${rachaMax === 1 ? 'día' : 'días'}`}
            nota={
              rachaActual > 0
                ? `viene de ${rachaActual} ${rachaActual === 1 ? 'día' : 'días'} seguidos`
                : 'hoy sin registrar'
            }
          />
          <Dato
            termino="Hueco más largo"
            valor={
              huecoMax
                ? `${huecoMax} ${huecoMax === 1 ? 'día' : 'días'}`
                : 'ninguno'
            }
            nota={huecoMax ? 'sin ninguna comida cargada' : 'no faltó ni un día'}
          />
          <Dato
            termino="Entre semana"
            valor={pct(semanaRegistrados, semana.length)}
            nota={`${semanaRegistrados} de ${semana.length} días`}
          />
          <Dato
            termino="Fines de semana"
            valor={pct(finesRegistrados, finesDeSemana.length)}
            nota={`${finesRegistrados} de ${finesDeSemana.length} días`}
          />
        </dl>
      </div>
    </div>
  );
}

function Dato({
  termino,
  valor,
  nota,
}: {
  termino: string;
  valor: string;
  nota: string;
}) {
  return (
    <div className="cal-fact">
      <dt className="caption">{termino}</dt>
      <dd className="tnum">{valor}</dd>
      <dd className="caption">{nota}</dd>
    </div>
  );
}
