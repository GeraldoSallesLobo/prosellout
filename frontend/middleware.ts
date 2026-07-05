import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

interface CookieToSet {
  name: string;
  value: string;
  options?: CookieOptions;
}

const LOGIN_PATH = "/login";
const HOME_PATH = "/relatorio/status/mtd";

/**
 * Session refresh + route protection.
 *
 * Demo mode (no Supabase env vars) leaves every route public so the design
 * can be reviewed without infra. To avoid failing open in production when the
 * env vars are accidentally missing, demo mode there requires the explicit
 * opt-in NEXT_PUBLIC_DEMO_MODE=true; otherwise requests are rejected.
 */
export async function middleware(request: NextRequest) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const isDemoMode = !supabaseUrl || !supabaseAnonKey;
  if (isDemoMode) {
    const isDemoAllowed =
      process.env.NODE_ENV !== "production" ||
      process.env.NEXT_PUBLIC_DEMO_MODE === "true";
    if (isDemoAllowed) return NextResponse.next();
    return new NextResponse(
      "Serviço indisponível: autenticação não configurada.",
      { status: 503 },
    );
  }

  let response = NextResponse.next({ request });

  const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (cookies: CookieToSet[]) => {
        cookies.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookies.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const isLoginRoute = request.nextUrl.pathname.startsWith(LOGIN_PATH);

  if (!user && !isLoginRoute) {
    return NextResponse.redirect(new URL(LOGIN_PATH, request.url));
  }
  if (user && isLoginRoute) {
    return NextResponse.redirect(new URL(HOME_PATH, request.url));
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|ico)$).*)"],
};
