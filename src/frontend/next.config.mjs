/** @type {import('next').NextConfig} */

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const uploadApiUrl = process.env.NEXT_PUBLIC_UPLOAD_API_URL ?? "";
const supabaseConnectSources = supabaseUrl
  ? `${supabaseUrl} ${supabaseUrl.replace(/^http/, "ws")}`
  : "";

function getOrigin(url) {
  if (!url) return "";
  try {
    return new URL(url).origin;
  } catch {
    return "";
  }
}

const uploadApiOrigin = getOrigin(uploadApiUrl);
const uploadConnectSources = [
  uploadApiOrigin,
  "https://*.amazonaws.com",
  "https://*.on.aws",
].filter(Boolean).join(" ");

// 'unsafe-inline'/'unsafe-eval' in script-src are required by the Next.js
// runtime and the inline theme script; the remaining directives keep embeds,
// plugins and untrusted connection origins blocked.
const contentSecurityPolicy = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self' data:",
  // The Supabase origin comes from the env so local dev (http://127.0.0.1:54321)
  // works — the wildcard alone only matches hosted projects.
  `connect-src 'self' https://*.supabase.co wss://*.supabase.co ${uploadConnectSources} ${supabaseConnectSources}`.trim(),
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
  // Without NEXT_PUBLIC_SUPABASE_* vars the portal runs in demo mode. The
  // middleware requires explicit NEXT_PUBLIC_DEMO_MODE=true in production to
  // avoid fail-open access; set Supabase env vars to use the real backend.
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

import('@opennextjs/cloudflare').then(m => m.initOpenNextCloudflareForDev());
