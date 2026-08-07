import {
  Anchor,
  ArrowDownToLine,
  ArrowUpFromLine,
  BarChart3,
  CalendarDays,
  CalendarRange,
  ClipboardList,
  Crosshair,
  Factory,
  History,
  Layers,
  LayoutDashboard,
  ListTree,
  Package,
  Percent,
  Radar,
  Route,
  Settings2,
  ShieldCheck,
  Shuffle,
  Store,
  Target,
  Upload,
  UserRound,
  Users,
  Wand2,
  Zap,
  type LucideIcon,
} from "lucide-react";
import { PLANNER_MODEL_LABELS } from "@/lib/planner";

export interface NavigationItem {
  label: string;
  href: string;
  icon: LucideIcon;
  visibility?: "all" | "admin" | "user";
}

export interface NavigationGroup {
  label: string;
  items: NavigationItem[];
}

/** Sidebar structure — mirrors the approved mockup menu. */
export const NAVIGATION_GROUPS: NavigationGroup[] = [
  {
    label: "Admin",
    items: [
      { label: "Usuários", href: "/admin/usuarios", icon: ShieldCheck, visibility: "admin" },
      { label: "Logs", href: "/admin/logs", icon: History, visibility: "admin" },
    ],
  },
  {
    label: "Cadastros",
    items: [
      { label: "Distribuidor", href: "/cadastros/distribuidor", icon: Factory },
      { label: "Hier. Produtos", href: "/cadastros/hierarquia-produtos", icon: ListTree },
      { label: "Hier. Comercial", href: "/cadastros/hierarquia-comercial", icon: Users },
    ],
  },
  {
    label: "Arquivos",
    items: [
      { label: "Importação", href: "/arquivos/importacao", icon: Upload, visibility: "user" },
      { label: "Configuração", href: "/arquivos/configuracao", icon: Settings2, visibility: "user" },
    ],
  },
  {
    label: "Dados",
    items: [
      { label: "Clientes", href: "/dados/clientes", icon: Store },
      { label: "Estoque", href: "/dados/estoque", icon: Package },
      { label: "Meta", href: "/dados/meta", icon: Target },
      { label: "Sell In", href: "/dados/sell-in", icon: ArrowDownToLine },
      { label: "Sell Out", href: "/dados/sell-out", icon: ArrowUpFromLine },
      { label: "Vendedores", href: "/dados/vendedores", icon: UserRound },
    ],
  },
  {
    label: "Relatório de Status",
    items: [
      { label: "Status MTD", href: "/relatorio/status/mtd", icon: ClipboardList },
      { label: "Análise Detalhada", href: "/relatorio/status/analise", icon: BarChart3 },
      { label: "Fast Facts", href: "/relatorio/status/fast-facts", icon: Zap },
    ],
  },
  {
    label: "Relatório de Evolução",
    items: [
      { label: "Análise Mensal", href: "/relatorio/evolucoes/mensal", icon: CalendarDays },
      { label: "Histórico 3M", href: "/relatorio/evolucoes/historico-3m", icon: CalendarRange },
      { label: "Análise Evolução", href: "/relatorio/evolucoes/analise", icon: Shuffle },
    ],
  },
  {
    label: "Planner",
    items: [
      { label: "Parametrização", href: "/planner/parametrizacao", icon: Route },
      { label: PLANNER_MODEL_LABELS.automatic, href: "/planner/automatico", icon: Wand2 },
      {
        label: PLANNER_MODEL_LABELS.battleship_volume,
        href: "/planner/batalha-naval-volume",
        icon: Anchor,
      },
      {
        label: PLANNER_MODEL_LABELS.battleship_positivation,
        href: "/planner/batalha-naval-positivacao",
        icon: Crosshair,
      },
      { label: PLANNER_MODEL_LABELS.coverage, href: "/planner/cobertura", icon: Radar },
      { label: PLANNER_MODEL_LABELS.profitability, href: "/planner/rentabilidade", icon: Percent },
      { label: "Planificadores", href: "/planner/planos", icon: Layers },
      { label: "Dashboard", href: "/planner/dashboard", icon: LayoutDashboard },
    ],
  },
];

export interface BreadcrumbTrail {
  group: string;
  page: string;
}

/** Resolves the breadcrumb (group › page) for a pathname. */
export function findBreadcrumb(pathname: string): BreadcrumbTrail | null {
  for (const group of NAVIGATION_GROUPS) {
    const item = group.items.find((candidate) => pathname.startsWith(candidate.href));
    if (item) return { group: group.label, page: item.label };
  }
  return null;
}
