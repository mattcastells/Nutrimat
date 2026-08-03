import { createBrowserClient } from '@supabase/ssr';

/**
 * El cliente del navegador, en su propio archivo.
 *
 * Va separado del de servidor porque aquel importa `next/headers`, y ese import
 * no se puede resolver en un Client Component: alcanza con que un archivo
 * compartido lo mencione para que el build falle entero. Dos archivos chicos en
 * vez de uno que no compila.
 *
 * Entra con la **publishable key**, nunca con la service-role: esa saltea RLS
 * por completo, así que en un frontend es una llave maestra a los datos de
 * todos. Lo que este panel puede ver lo decide Postgres a partir de
 * `care_grants`.
 */
export function browserClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  );
}
