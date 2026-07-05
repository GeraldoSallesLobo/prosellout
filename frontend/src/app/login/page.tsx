"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { TextField } from "@/components/ui/field";
import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/ui/theme-toggle";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { isDemoMode } from "@/lib/env";

const HOME_ROUTE = "/relatorio/status/mtd";
const LOGIN_THEME_ICON_SIZE = 18;

/** Maps GoTrue/network errors to actionable messages (pt-BR). */
function resolveLoginErrorMessage(rawMessage: string): string {
  const message = rawMessage.toLowerCase();
  if (message.includes("email not confirmed")) {
    return "E-mail não confirmado. Recrie o usuário no Studio marcando 'Auto Confirm User' ou confirme-o em Authentication › Users.";
  }
  if (message.includes("fetch") || message.includes("network")) {
    return "Não foi possível conectar ao Supabase. Verifique se o 'supabase start' está rodando e reinicie o npm run dev.";
  }
  return "E-mail ou senha inválidos.";
}

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setErrorMessage(null);

    const supabase = getSupabaseBrowserClient();
    if (!supabase) {
      router.push(HOME_ROUTE);
      return;
    }

    setIsSubmitting(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setIsSubmitting(false);

    if (error) {
      setErrorMessage(resolveLoginErrorMessage(error.message));
      return;
    }
    router.push(HOME_ROUTE);
    router.refresh();
  }

  return (
    <div className="login-bg relative flex min-h-screen items-center justify-center p-4">
      <ThemeToggle
        iconSize={LOGIN_THEME_ICON_SIZE}
        className="absolute right-4 top-4 rounded-md p-2 text-text2 transition-colors hover:bg-text1/5 hover:text-text1"
      />
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <div className="text-2xl font-extrabold tracking-tight text-blue">ProSellOut</div>
          <p className="mt-1 text-sm text-text2">Portal de gestão de Sell Out</p>
        </div>

        <form onSubmit={handleSubmit} className="card space-y-4 p-6">
          <TextField
            label="E-mail"
            type="email"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="voce@empresa.com.br"
          />
          <TextField
            label="Senha"
            type="password"
            required={!isDemoMode}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder="••••••••"
          />

          {errorMessage ? (
            <p className="rounded-md border border-red/40 bg-red/10 px-3 py-2 text-xs text-red">
              {errorMessage}
            </p>
          ) : null}

          <Button type="submit" className="w-full" disabled={isSubmitting}>
            {isSubmitting ? "Entrando..." : "Entrar"}
          </Button>

          {isDemoMode ? (
            <p className="text-center text-xs text-yellow">
              Modo demo: qualquer credencial dá acesso com dados de exemplo.
            </p>
          ) : null}
        </form>
      </div>
    </div>
  );
}
