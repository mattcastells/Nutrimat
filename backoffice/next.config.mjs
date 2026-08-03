/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  // Las fotos llegan como URL firmada del bucket privado y vencen. Se muestran
  // con <img> y no con next/image a propósito: el optimizador cachearía en el
  // borde una imagen que la firma vuelve inaccesible en una hora, y una foto de
  // la comida de alguien no tiene por qué quedar guardada en un CDN.
  images: { unoptimized: true },

  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          // El panel muestra datos de salud: que no lo indexe nadie.
          { key: 'X-Robots-Tag', value: 'noindex, nofollow' },
          { key: 'Referrer-Policy', value: 'same-origin' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'X-Frame-Options', value: 'DENY' },
        ],
      },
    ];
  },
};

export default nextConfig;
