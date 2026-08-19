'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { browserClient } from '@/lib/supabase-browser';
import { fechaLarga, hoyISO } from '@/lib/format';
import type { CareNote } from '@/lib/queries';

/**
 * Lo que anota la profesional.
 *
 * Es **la única escritura del panel**, y hay que leer con precisión qué
 * significa eso: lo que sigue sin poder escribirse son los datos del paciente.
 * Si esta pantalla intentara corregir un peso o borrar una comida, la base lo
 * rechaza igual que antes. Lo que se abrió es una tabla donde se escribe lo
 * propio (`care_notes`, migración 42).
 *
 * Sin esto, la consulta se prepara en un cuaderno aparte y la pantalla que
 * tiene los datos no tiene la lectura de esos datos.
 *
 * **Las lee solo quien las escribió.** El paciente no las ve. Una observación
 * clínica que el paciente va a leer se escribe distinto —o no se escribe— y
 * termina siendo un mensaje en vez de una nota de trabajo.
 *
 * Escribe desde el navegador con la sesión de quien mira, como el resto del
 * panel: no hay ninguna ruta de servidor que escriba a nombre de nadie, así que
 * lo que se puede guardar lo sigue decidiendo la policy y no este código.
 */
export function Notes({
  patientId,
  notes,
  patientName,
}: {
  patientId: string;
  notes: CareNote[];
  patientName: string | null;
}) {
  const router = useRouter();
  const [texto, setTexto] = useState('');
  const [fecha, setFecha] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [pendiente, startTransition] = useTransition();
  const [editando, setEditando] = useState<string | null>(null);
  const [borrador, setBorrador] = useState('');

  const refrescar = () => startTransition(() => router.refresh());

  async function guardar() {
    const cuerpo = texto.trim();
    if (!cuerpo) return;
    setGuardando(true);
    setError(null);

    const { error: err } = await browserClient()
      .from('care_notes')
      .insert({
        patient_id: patientId,
        // `null` = una nota del seguimiento en general; con fecha queda anclada
        // a ese día y aparece al abrirlo en el día a día.
        local_date: fecha || null,
        body: cuerpo,
      });

    setGuardando(false);
    if (err) {
      // El mensaje crudo de Postgres no le dice nada a nadie, pero el caso real
      // sí tiene una explicación: la policy exige un permiso vigente, así que
      // un error acá casi siempre es un acceso que el paciente revocó.
      setError(
        'No se pudo guardar. Si el paciente revocó el acceso, las notas que ya ' +
          'escribiste siguen estando pero no se pueden agregar nuevas.',
      );
      return;
    }
    setTexto('');
    setFecha('');
    refrescar();
  }

  async function editar(id: string) {
    const cuerpo = borrador.trim();
    if (!cuerpo) return;
    await browserClient()
      .from('care_notes')
      .update({ body: cuerpo })
      .eq('id', id);
    setEditando(null);
    refrescar();
  }

  async function borrar(id: string) {
    // Lápida y no borrado: la ventana de 30 días de `purge_soft_deleted` es la
    // misma que para todo lo demás, y un borrado accidental de una nota de
    // consulta no se recupera de ningún lado.
    await browserClient()
      .from('care_notes')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', id);
    refrescar();
  }

  const generales = notes.filter((n) => !n.local_date);
  const conFecha = notes.filter((n) => n.local_date);

  return (
    <>
      <div className="card">
        <label className="caption" htmlFor="nota">
          Nueva nota
        </label>
        <textarea
          id="nota"
          className="note-input"
          rows={4}
          maxLength={4000}
          value={texto}
          placeholder={`Qué observaste, qué acordaron, qué mirar la próxima vez${
            patientName ? ` con ${patientName.split(' ')[0]}` : ''
          }.`}
          onChange={(e) => setTexto(e.target.value)}
        />

        <div className="row" style={{ marginTop: 'var(--s3)', flexWrap: 'wrap' }}>
          <label className="caption" htmlFor="nota-fecha">
            Anclar a un día (opcional)
          </label>
          <input
            id="nota-fecha"
            type="date"
            className="note-date"
            value={fecha}
            max={hoyISO()}
            onChange={(e) => setFecha(e.target.value)}
          />
          <button
            onClick={guardar}
            disabled={guardando || !texto.trim()}
            style={{ marginLeft: 'auto' }}
          >
            {guardando ? 'Guardando…' : 'Guardar'}
          </button>
        </div>

        {error && (
          <p className="caption" style={{ color: 'var(--caution)' }}>
            {error}
          </p>
        )}

        <p className="caption" style={{ marginTop: 'var(--s3)' }}>
          Las notas son tuyas: el paciente no las ve.
        </p>
      </div>

      {notes.length === 0 && (
        <div className="card" style={{ marginTop: 'var(--s3)' }}>
          <p className="muted" style={{ margin: 0 }}>
            Todavía no anotaste nada sobre este seguimiento.
          </p>
        </div>
      )}

      {conFecha.length > 0 && (
        <>
          <div className="section-header">Sobre un día</div>
          {conFecha.map((n) => (
            <Nota
              key={n.id}
              nota={n}
              editando={editando === n.id}
              borrador={borrador}
              onBorrador={setBorrador}
              onEditar={() => {
                setEditando(n.id);
                setBorrador(n.body);
              }}
              onCancelar={() => setEditando(null)}
              onGuardar={() => editar(n.id)}
              onBorrar={() => borrar(n.id)}
              ocupado={pendiente}
            />
          ))}
        </>
      )}

      {generales.length > 0 && (
        <>
          <div className="section-header">Del seguimiento</div>
          {generales.map((n) => (
            <Nota
              key={n.id}
              nota={n}
              editando={editando === n.id}
              borrador={borrador}
              onBorrador={setBorrador}
              onEditar={() => {
                setEditando(n.id);
                setBorrador(n.body);
              }}
              onCancelar={() => setEditando(null)}
              onGuardar={() => editar(n.id)}
              onBorrar={() => borrar(n.id)}
              ocupado={pendiente}
            />
          ))}
        </>
      )}
    </>
  );
}

function Nota({
  nota,
  editando,
  borrador,
  onBorrador,
  onEditar,
  onCancelar,
  onGuardar,
  onBorrar,
  ocupado,
}: {
  nota: CareNote;
  editando: boolean;
  borrador: string;
  onBorrador: (v: string) => void;
  onEditar: () => void;
  onCancelar: () => void;
  onGuardar: () => void;
  onBorrar: () => void;
  ocupado: boolean;
}) {
  const [confirmar, setConfirmar] = useState(false);

  return (
    <div className="card" style={{ marginBottom: 'var(--s3)' }}>
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <span className="caption">
          {nota.local_date
            ? fechaLarga(nota.local_date)
            : new Date(nota.created_at).toLocaleDateString('es-AR', {
                day: 'numeric',
                month: 'long',
              })}
          {nota.updated_at !== nota.created_at && ' · editada'}
        </span>
        <span className="chips">
          {editando ? (
            <>
              <button onClick={onGuardar} disabled={ocupado}>
                Guardar
              </button>
              <button className="ghost" onClick={onCancelar}>
                Cancelar
              </button>
            </>
          ) : (
            <>
              <button className="ghost" onClick={onEditar}>
                Editar
              </button>
              {/* Dos toques para borrar. Es la única acción destructiva del
                  panel y no hay papelera a la vista: la lápida se purga a los
                  30 días y de ahí no vuelve. */}
              <button
                className="ghost"
                onClick={() => (confirmar ? onBorrar() : setConfirmar(true))}
              >
                {confirmar ? '¿Seguro?' : 'Borrar'}
              </button>
            </>
          )}
        </span>
      </div>

      {editando ? (
        <textarea
          className="note-input"
          rows={4}
          maxLength={4000}
          value={borrador}
          onChange={(e) => onBorrador(e.target.value)}
        />
      ) : (
        <p className="note-body">{nota.body}</p>
      )}
    </div>
  );
}
