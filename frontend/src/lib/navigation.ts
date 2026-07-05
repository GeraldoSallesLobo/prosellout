import {
  Anchor,
  ArrowDownToLine,
  ArrowUpFromLine,
  BarChart3,
  CalendarDays,
  CalendarRange,
  ClipboardList,
  Factory,
  ListTree,
  Package,
  Settings2,
  Shuffle,
  Store,
  Target,
  Upload,
  UserRound,
  Users,
  Zap,
  type LucideIcon,
} from "lucide-react";

export interface NavigationItem {
  label: string;
  href: string;
  icon: LucideIcon;
}

export interface NavigationGroup {
  label: string;
  items: NavigationItem[];
}

/** Sidebar structure — mirrors the approved mockup menu. */
export const NAVIGATION_GROUPS: NavigationGroup[] = [
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
      { label: "Importação", href: "/arquivos/importacao", icon: Upload },
      { label: "Configuração", href: "/arquivos/configuracao", icon: Settings2 },
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
      { label: "Análise", href: "/relatorio/status/analise", icon: BarChart3 },
      { label: "Fast Facts", href: "/relatorio/status/fast-facts", icon: Zap },
    ],
  },
  {
    label: "Rel. Evoluções",
    items: [
      { label: "Análise Mensal", href: "/relatorio/evolucoes/mensal", icon: CalendarDays },
      { label: "Histórico 3M", href: "/relatorio/evolucoes/historico-3m", icon: CalendarRange },
      { label: "Análise", href: "/relatorio/evolucoes/analise", icon: Shuffle },
    ],
  },
  {
    label: "Planificador",
    items: [
      { label: "Batalha Naval", href: "/planificador/batalha-naval", icon: Anchor },
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
