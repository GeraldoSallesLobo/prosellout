export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
export const UPLOAD_API_URL = process.env.NEXT_PUBLIC_UPLOAD_API_URL ?? "";

/**
 * When Supabase is not configured the portal runs in demo mode: every
 * repository serves deterministic sample data so the UI can be reviewed
 * without any infrastructure.
 */
export const isSupabaseConfigured =
  SUPABASE_URL.length > 0 && SUPABASE_ANON_KEY.length > 0;

export const isDemoMode = !isSupabaseConfigured;
