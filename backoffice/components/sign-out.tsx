'use client';

import { useRouter } from 'next/navigation';
import { browserClient } from '@/lib/supabase-browser';

export function SignOut() {
  const router = useRouter();

  return (
    <button
      onClick={async () => {
        await browserClient().auth.signOut();
        router.replace('/login');
        router.refresh();
      }}
      style={{ border: '1px solid var(--divider)', color: 'var(--text-muted)' }}
    >
      Salir
    </button>
  );
}
