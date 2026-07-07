"use client";

import { createContext, useCallback, useContext, useMemo, useState } from "react";
import { CheckCircle2, Info, XCircle } from "lucide-react";
import clsx from "clsx";

type ToastVariant = "success" | "error" | "info";

interface ToastMessage {
  id: number;
  variant: ToastVariant;
  text: string;
}

interface ToastContextValue {
  showToast: (variant: ToastVariant, text: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

const TOAST_DURATION_MS = 4000;

const VARIANT_STYLES: Record<ToastVariant, string> = {
  success: "border-green/40 text-green",
  error: "border-red/40 text-red",
  info: "border-blue/40 text-blue",
};

const VARIANT_ICONS: Record<ToastVariant, typeof Info> = {
  success: CheckCircle2,
  error: XCircle,
  info: Info,
};

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  const showToast = useCallback((variant: ToastVariant, text: string) => {
    const id = Date.now() + Math.random();
    setToasts((current) => [...current, { id, variant, text }]);
    setTimeout(() => {
      setToasts((current) => current.filter((toast) => toast.id !== id));
    }, TOAST_DURATION_MS);
  }, []);

  const value = useMemo(() => ({ showToast }), [showToast]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="pointer-events-none fixed bottom-5 right-5 z-50 flex w-80 flex-col gap-2">
        {toasts.map((toast) => {
          const Icon = VARIANT_ICONS[toast.variant];
          return (
            <div
              key={toast.id}
              className={clsx(
                "pointer-events-auto flex items-start gap-2.5 rounded-card border bg-bg2 px-4 py-3 text-sm shadow-lg",
                VARIANT_STYLES[toast.variant],
              )}
            >
              <Icon size={16} className="mt-0.5 shrink-0" />
              <span className="text-text1">{toast.text}</span>
            </div>
          );
        })}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const context = useContext(ToastContext);
  if (!context) throw new Error("useToast must be used inside ToastProvider");
  return context;
}
