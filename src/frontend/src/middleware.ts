import { NextResponse, type NextRequest } from "next/server";
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { SUPABASE_ANON_KEY, SUPABASE_URL, isSupabaseConfigured } from "@/lib/env";

const LOGIN_ROUTE = "/login";
const HOME_ROUTE = "/relatorio/status/mtd";

/**
 * Guards every portal route: unauthenticated visitors are sent to /login and
 * already-authenticated ones are kept out of the login screen. Runs on the edge
 * before the page renders, so protected content is never served to a signed-out
 * user. In demo mode there is no Supabase, so the gate is skipped entirely.
 */
export async function middleware(request: NextRequest) {
  if (!isSupabaseConfigured) return NextResponse.next();

  // Mutable because Supabase may rotate the session cookie mid-request; the
  // refreshed response has to carry those Set-Cookie headers back to the browser.
  let response = NextResponse.next({ request });

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          response.cookies.set(name, value, options),
        );
      },
    },
  });

  // getUser() revalidates the token against the auth server, unlike getSession().
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const isLoginRoute = request.nextUrl.pathname === LOGIN_ROUTE;

  if (!user && !isLoginRoute) {
    const url = request.nextUrl.clone();
    url.pathname = LOGIN_ROUTE;
    return NextResponse.redirect(url);
  }

  if (user && isLoginRoute) {
    const url = request.nextUrl.clone();
    url.pathname = HOME_ROUTE;
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  // Skip Next internals and static assets; the auth gate only matters for pages.
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
