/** @type {import('next').NextConfig} */

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const supabaseConnectSources = supabaseUrl
  ? `${supabaseUrl} ${supabaseUrl.replace(/^http/, "ws")}`
  : "";

// 'unsafe-inline'/'unsafe-eval' em script-src são exigidos pelo runtime do
// Next.js (e pelo script inline de tema); os demais diretivos continuam
// bloqueando embedding, plugins e conexões a origens não confiáveis.
const contentSecurityPolicy = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self' data:",
  // The Supabase origin comes from the env so local dev (http://127.0.0.1:54321)
  // works — the wildcard alone only matches hosted projects.
  `connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.amazonaws.com ${supabaseConnectSources}`.trim(),
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: contentSecurityPolicy },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
];

const nextConfig = {
  reactStrictMode: true,
  // Sem NEXT_PUBLIC_SUPABASE_* definidas, o portal roda em modo demo. O
  // middleware exige o opt-in explícito NEXT_PUBLIC_DEMO_MODE=true para não
  // retornar 503 em produção (fail-closed). Este default liga o demo por
  // padrão no deploy; defina as vars do Supabase no Vercel para usar o backend
  // real, ou NEXT_PUBLIC_DEMO_MODE=false para exigir autenticação.
  env: {
    NEXT_PUBLIC_DEMO_MODE: process.env.NEXT_PUBLIC_DEMO_MODE ?? "true",
  },
  eslint: {
    // Linting runs in CI (`npm run lint`); skip during production builds.
    ignoreDuringBuilds: true,
  },
  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },
};

export default nextConfig;
