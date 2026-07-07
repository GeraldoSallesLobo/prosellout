"use client";

import { useEffect, useState } from "react";
import { Menu } from "lucide-react";
import { Breadcrumb } from "@/components/layout/breadcrumb";
import { Sidebar } from "@/components/layout/sidebar";

interface PortalShellProps {
  children: React.ReactNode;
}

export function PortalShell({ children }: PortalShellProps) {
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  useEffect(() => {
    if (!isMobileMenuOpen) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setIsMobileMenuOpen(false);
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isMobileMenuOpen]);

  function openMobileMenu() {
    setIsMobileMenuOpen(true);
  }

  function closeMobileMenu() {
    setIsMobileMenuOpen(false);
  }

  return (
    <div className="flex h-screen overflow-hidden bg-bg">
      <Sidebar />

      {isMobileMenuOpen ? (
        <div className="md:hidden">
          <button
            type="button"
            aria-label="Fechar menu"
            className="fixed inset-0 z-40 cursor-default bg-bg/75 backdrop-blur-sm"
            onClick={closeMobileMenu}
          />
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Menu principal"
            className="fixed inset-y-0 left-0 z-50"
          >
            <Sidebar
              variant="mobile"
              onClose={closeMobileMenu}
              onNavigate={closeMobileMenu}
            />
          </div>
        </div>
      ) : null}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-12 shrink-0 items-center gap-3 border-b border-line bg-bg px-4 md:px-6">
          <button
            type="button"
            onClick={openMobileMenu}
            aria-label="Abrir menu"
            className="rounded-md p-1.5 text-text2 transition-colors hover:bg-text1/5 hover:text-text1 md:hidden"
          >
            <Menu size={18} />
          </button>
          <Breadcrumb />
        </header>
        <main className="min-w-0 flex-1 overflow-y-auto p-4 md:p-6">{children}</main>
      </div>
    </div>
  );
}
