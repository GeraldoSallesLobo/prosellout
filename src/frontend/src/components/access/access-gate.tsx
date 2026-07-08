"use client";

import { useQuery } from "@tanstack/react-query";
import type { ReactElement, ReactNode } from "react";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";

interface AccessGateProps {
  children: ReactNode;
}

function AccessMessage({
  title,
  description,
}: {
  title: string;
  description: string;
}): ReactElement {
  return (
    <div className="card p-6">
      <h1 className="text-lg font-semibold text-text1">{title}</h1>
      <p className="mt-2 text-sm text-text2">{description}</p>
    </div>
  );
}

export function AdminOnly({ children }: AccessGateProps): ReactElement | ReactNode {
  const { data: access, isLoading } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });

  if (isLoading) {
    return <AccessMessage title="Carregando acesso" description="Validando seu perfil." />;
  }

  if (!access?.isAdmin) {
    return (
      <AccessMessage
        title="Acesso restrito"
        description="Esta área é exclusiva para administradores."
      />
    );
  }

  return children;
}

export function UserOnly({ children }: AccessGateProps): ReactElement | ReactNode {
  const { data: access, isLoading } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });

  if (isLoading) {
    return <AccessMessage title="Carregando acesso" description="Validando seu perfil." />;
  }

  if (access?.isAdmin) {
    return (
      <AccessMessage
        title="Acesso indisponível"
        description="Administradores não realizam importação de arquivos."
      />
    );
  }

  return children;
}
