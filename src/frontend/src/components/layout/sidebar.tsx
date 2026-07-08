"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import {
  ChevronDown,
  LogOut,
  PanelLeftClose,
  PanelLeftOpen,
  X,
} from "lucide-react";
import clsx from "clsx";
import { NAVIGATION_GROUPS } from "@/lib/navigation";
import {
  CURRENT_USER_ACCESS_QUERY_KEY,
  fetchCurrentUserAccess,
} from "@/lib/data/access";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { isDemoMode } from "@/lib/env";
import { useLocalStorageState } from "@/hooks/use-local-storage-state";
import { ThemeToggle } from "@/components/ui/theme-toggle";
import { BrandLogo } from "@/components/ui/brand-logo";

const SIDEBAR_COLLAPSED_STORAGE_KEY = "prosellout.sidebar.is-collapsed";
const COLLAPSED_GROUPS_STORAGE_KEY = "prosellout.sidebar.collapsed-groups";
const NAV_ICON_SIZE = 15;
const TOGGLE_ICON_SIZE = 16;
const CHEVRON_ICON_SIZE = 12;

interface SidebarProps {
  onClose?: () => void;
  onNavigate?: () => void;
  variant?: "desktop" | "mobile";
}

export function Sidebar({ onClose, onNavigate, variant = "desktop" }: SidebarProps) {
  const pathname = usePathname();
  const router = useRouter();
  const isMobile = variant === "mobile";

  const [isDesktopCollapsed, setIsDesktopCollapsed] = useLocalStorageState(
    SIDEBAR_COLLAPSED_STORAGE_KEY,
    false,
  );
  const [collapsedGroups, setCollapsedGroups] = useLocalStorageState<string[]>(
    COLLAPSED_GROUPS_STORAGE_KEY,
    [],
  );
  const { data: access } = useQuery({
    queryKey: CURRENT_USER_ACCESS_QUERY_KEY,
    queryFn: fetchCurrentUserAccess,
  });

  const isCollapsed = !isMobile && isDesktopCollapsed;
  const visibleNavigationGroups = NAVIGATION_GROUPS.map((group) => ({
    ...group,
    items: group.items.filter((item) => {
      if (item.visibility === "admin") return access?.isAdmin === true;
      if (item.visibility === "user") return access ? !access.isAdmin : false;
      return true;
    }),
  })).filter((group) => group.items.length > 0);

  async function handleSignOut() {
    onNavigate?.();
    const supabase = getSupabaseBrowserClient();
    if (supabase) {
      await supabase.auth.signOut();
      router.push("/login");
      return;
    }
    router.push("/login");
  }

  function toggleSidebar() {
    setIsDesktopCollapsed((current) => !current);
  }

  function toggleGroup(groupLabel: string) {
    setCollapsedGroups((current) =>
      current.includes(groupLabel)
        ? current.filter((label) => label !== groupLabel)
        : [...current, groupLabel],
    );
  }

  return (
    <aside
      className={clsx(
        "flex shrink-0 flex-col border-r border-line bg-bg2",
        isMobile
          ? "h-full w-72 max-w-[calc(100vw-3rem)] shadow-xl"
          : "hidden h-screen transition-[width] duration-200 md:flex",
        !isMobile && (isCollapsed ? "w-14" : "w-56"),
      )}
    >
      <div
        className={clsx(
          "flex items-center pb-4 pt-5",
          isCollapsed ? "justify-center px-2" : "justify-between px-5",
        )}
      >
        {!isCollapsed && (
          <div>
            <Link href="/relatorio/status/mtd" className="block w-fit">
              <BrandLogo priority />
            </Link>
            {isDemoMode ? (
              <span className="mt-2 block text-[10px] font-semibold uppercase tracking-widest text-yellow">
                modo demo
              </span>
            ) : null}
          </div>
        )}
        {isMobile ? (
          <button
            type="button"
            onClick={onClose}
            title="Fechar menu"
            aria-label="Fechar menu"
            className="rounded-md p-1.5 text-text2 transition-colors hover:bg-text1/5 hover:text-text1"
          >
            <X size={TOGGLE_ICON_SIZE} />
          </button>
        ) : (
          <button
            type="button"
            onClick={toggleSidebar}
            title={isCollapsed ? "Expandir menu" : "Recolher menu"}
            aria-label={isCollapsed ? "Expandir menu" : "Recolher menu"}
            className="rounded-md p-1.5 text-text2 transition-colors hover:bg-text1/5 hover:text-text1"
          >
            {isCollapsed ? (
              <PanelLeftOpen size={TOGGLE_ICON_SIZE} />
            ) : (
              <PanelLeftClose size={TOGGLE_ICON_SIZE} />
            )}
          </button>
        )}
      </div>

      <nav
        className={clsx(
          "flex-1 space-y-5 overflow-y-auto pb-4",
          isCollapsed ? "px-2" : "px-3",
        )}
      >
        {visibleNavigationGroups.map((group, groupIndex) => {
          const isGroupCollapsed = collapsedGroups.includes(group.label);
          const isFirstGroup = groupIndex === 0;
          const shouldShowItems = isCollapsed || !isGroupCollapsed;

          return (
            <div key={group.label}>
              {isCollapsed ? (
                !isFirstGroup && <div className="mx-1 mb-2 border-t border-line" />
              ) : (
                <button
                  type="button"
                  onClick={() => toggleGroup(group.label)}
                  aria-expanded={!isGroupCollapsed}
                  className="flex w-full items-center justify-between rounded-md px-2 pb-1.5 text-[10px] font-bold uppercase tracking-[0.12em] text-text2 transition-colors hover:text-text1"
                >
                  {group.label}
                  <ChevronDown
                    size={CHEVRON_ICON_SIZE}
                    className={clsx(
                      "shrink-0 transition-transform",
                      isGroupCollapsed && "-rotate-90",
                    )}
                  />
                </button>
              )}

              {shouldShowItems && (
                <div className="space-y-0.5">
                  {group.items.map((item) => {
                    const isActive = pathname.startsWith(item.href);
                    const Icon = item.icon;
                    return (
                      <Link
                        key={item.href}
                        href={item.href}
                        onClick={onNavigate}
                        title={isCollapsed ? item.label : undefined}
                        className={clsx(
                          "flex items-center gap-2.5 rounded-md py-1.5 text-[13px] transition-colors",
                          isCollapsed ? "justify-center px-0" : "px-2",
                          isActive
                            ? "bg-accent2/15 font-semibold text-blue"
                            : "text-text3 hover:bg-text1/5 hover:text-text1",
                        )}
                      >
                        <Icon
                          size={NAV_ICON_SIZE}
                          className={clsx("shrink-0", isActive ? "text-blue" : "text-text2")}
                        />
                        {!isCollapsed && item.label}
                      </Link>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </nav>

      <ThemeToggle
        showLabel={!isCollapsed}
        iconSize={NAV_ICON_SIZE}
        className={clsx(
          "flex items-center gap-2.5 border-t border-line py-3 text-[13px] text-text2 transition-colors hover:text-text1",
          isCollapsed ? "justify-center px-2" : "px-5",
        )}
      />

      <button
        type="button"
        onClick={handleSignOut}
        title={isCollapsed ? "Sair" : undefined}
        className={clsx(
          "flex items-center gap-2.5 border-t border-line py-3.5 text-[13px] text-text2 transition-colors hover:text-red",
          isCollapsed ? "justify-center px-2" : "px-5",
        )}
      >
        <LogOut size={NAV_ICON_SIZE} className="shrink-0" />
        {!isCollapsed && "Sair"}
      </button>
    </aside>
  );
}
