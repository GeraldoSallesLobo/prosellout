export type ImportLayoutStatus = "ready" | "planned" | "calculated";

export interface ImportConfigReference {
  code: string;
  name: string;
  targetTable: string;
}

export interface ImportLayoutSpec {
  code: string;
  title: string;
  screen: string;
  targetTable: string;
  status: ImportLayoutStatus;
  summary: string;
  prerequisiteCodes: string[];
  requiredColumns: string[];
  optionalColumns: string[];
  notes: string[];
}

const IMPORT_LAYOUT_SPECS: ImportLayoutSpec[] = [
  {
    code: "CUSTOMERS",
    title: "Clientes",
    screen: "Dados › Clientes",
    targetTable: "customers",
    status: "ready",
    summary: "Atualiza os PDVs/clientes do distribuidor, canal e cluster.",
    prerequisiteCodes: [],
    requiredColumns: ["CNPJ Distribuidor", "Cód. PDV", "Razão Social"],
    optionalColumns: [
      "CNPJ/CPF",
      "Nome Fantasia",
      "Endereço",
      "Bairro",
      "Cidade",
      "UF",
      "CEP",
      "Canal do PDV",
      "CLUSTER",
    ],
    notes: [
      "O PDV é identificado por distribuidor + Cód. PDV.",
      "Canal e cluster são criados/reativados automaticamente quando informados.",
    ],
  },
  {
    code: "PRODUCTS",
    title: "Hier. Produtos",
    screen: "Cadastros › Hier. Produtos",
    targetTable: "products",
    status: "ready",
    summary: "Atualiza produtos e a árvore macro categoria › categoria › subcategoria.",
    prerequisiteCodes: [],
    requiredColumns: [
      "CNPJ Distribuidor",
      "EAN",
      "Descrição",
      "SubCategoria",
      "Categoria",
      "Macrocategoria",
    ],
    optionalColumns: ["Caixa", "Unidades", "CÓD SKU"],
    notes: [
      "EAN de 13 e 14 dígitos é normalizado no cruzamento com sell-out/sell-in.",
      "Se Unidades vier vazio, o sistema assume 1 unidade por embalagem.",
    ],
  },
  {
    code: "SELLERS",
    title: "Vendedores",
    screen: "Dados › Vendedores",
    targetTable: "sales_reps",
    status: "ready",
    summary: "Atualiza vendedores e seus supervisores na hierarquia comercial.",
    prerequisiteCodes: [],
    requiredColumns: ["CNPJ Distribuidor", "Cód. Vendedor", "Nome Vendedor", "Cód. Supervisor"],
    optionalColumns: [
      "Quantidade clientes (carteira)",
      "Nome Supervisor",
      "Cód. Gerente",
      "Nome Gerente",
    ],
    notes: [
      "Supervisores são criados automaticamente a partir do código informado.",
      "Gerente é preservado como dado de layout, mas ainda não alimenta uma hierarquia própria.",
    ],
  },
  {
    code: "TARGETS",
    title: "Meta",
    screen: "Dados › Meta",
    targetTable: "sales_targets",
    status: "ready",
    summary: "Grava metas por cliente, produto, vendedor e mês.",
    prerequisiteCodes: ["PRODUCTS", "SELLERS", "CUSTOMERS"],
    requiredColumns: [
      "CNPJ Distribuidor",
      "EAN",
      "Cód. PDV",
      "Cód. Vendedor",
      "Volume Total de Unidades NF",
      "Valor Total R$ NF",
      "Data Faturamento",
    ],
    optionalColumns: ["Data Entrega", "CNPJ/CPF"],
    notes: [
      "Data Faturamento define o mês da meta.",
      "Linhas repetidas no mesmo cliente + SKU + vendedor + mês são somadas dentro da importação.",
    ],
  },
  {
    code: "SELL_OUT",
    title: "Sell Out",
    screen: "Dados › Sell Out",
    targetTable: "sell_out",
    status: "ready",
    summary: "Grava vendas do distribuidor para PDV/cliente por produto.",
    prerequisiteCodes: ["PRODUCTS", "SELLERS", "CUSTOMERS"],
    requiredColumns: [
      "CNPJ Distribuidor",
      "EAN",
      "Cód. PDV",
      "Cód. Vendedor",
      "Volume Total de Unidades NF",
      "Valor Total R$ NF",
      "Data Faturamento",
    ],
    optionalColumns: ["Data Entrega", "NF", "Custo Unitário", "CNPJ/CPF"],
    notes: [
      "Produto, vendedor e cliente precisam existir para alimentar os relatórios corretamente.",
      "Quando NF não vem no arquivo, o sistema cria um número técnico por linha importada.",
    ],
  },
  {
    code: "SELL_IN",
    title: "Sell In",
    screen: "Dados › Sell In",
    targetTable: "sell_in",
    status: "ready",
    summary: "Grava compras/entrada do distribuidor por produto.",
    prerequisiteCodes: ["PRODUCTS"],
    requiredColumns: [
      "CNPJ Distribuidor",
      "EAN",
      "Volume Total de Unidades NF",
      "Valor Total R$ NF",
      "Data de Faturamento",
    ],
    optionalColumns: ["NF", "Custo Unitário"],
    notes: [
      "Produto precisa existir em Hier. Produtos.",
      "Quando NF não vem no arquivo, o sistema cria um número técnico por linha importada.",
    ],
  },
  {
    code: "STOCK",
    title: "Estoque",
    screen: "Dados › Estoque",
    targetTable: "stock_snapshots",
    status: "calculated",
    summary: "Não é importado por arquivo; a tela calcula estoque por produto.",
    prerequisiteCodes: [],
    requiredColumns: [],
    optionalColumns: [],
    notes: [
      "Quantidade = Sell In acumulado − Sell Out acumulado até a data de referência.",
      "Saldo negativo é exibido como alerta de inconsistência nos dados.",
      "Valor Sell In é a soma acumulada do valor informado nos arquivos de Sell In.",
    ],
  },
  {
    code: "PLANNER",
    title: "Batalha Naval",
    screen: "Planificador › Batalha Naval",
    targetTable: "planner_entries",
    status: "planned",
    summary: "Representará entradas ou recomendações da matriz cliente × SKU.",
    prerequisiteCodes: ["PRODUCTS", "SELLERS", "CUSTOMERS"],
    requiredColumns: ["Cód. PDV", "EAN", "Cód. Vendedor", "Prioridade ou Recomendação"],
    optionalColumns: ["Volume Sugerido", "Valor Sugerido", "Motivo", "Data Referência"],
    notes: [
      "Ainda não existe tabela real no banco; a amostra vai definir se será importação própria ou cálculo derivado.",
      "A tela atual usa uma matriz demo até a regra real ser fechada.",
    ],
  },
];

const SPECS_BY_CODE = new Map(IMPORT_LAYOUT_SPECS.map((spec) => [spec.code, spec]));
const SPECS_BY_TARGET_TABLE = new Map(
  IMPORT_LAYOUT_SPECS.map((spec) => [spec.targetTable, spec]),
);

export function getImportLayoutSpec(
  config: ImportConfigReference | null | undefined,
): ImportLayoutSpec | null {
  if (!config) return null;
  return SPECS_BY_CODE.get(config.code) ?? SPECS_BY_TARGET_TABLE.get(config.targetTable) ?? null;
}

export function getImportDisplayName(config: ImportConfigReference): string {
  return getImportLayoutSpec(config)?.title ?? config.name;
}

export function getImportScreenLabel(config: ImportConfigReference): string {
  return getImportLayoutSpec(config)?.screen ?? config.name;
}

export function getImportLayoutSpecByCode(code: string): ImportLayoutSpec | null {
  return SPECS_BY_CODE.get(code) ?? null;
}

export function getImportPrerequisiteSpecs(spec: ImportLayoutSpec): ImportLayoutSpec[] {
  return spec.prerequisiteCodes.flatMap((code) => {
    const prerequisite = getImportLayoutSpecByCode(code);
    return prerequisite ? [prerequisite] : [];
  });
}

export function getMissingImportPrerequisiteCodes(
  spec: ImportLayoutSpec,
  completedImportCodes: Set<string>,
): string[] {
  return spec.prerequisiteCodes.filter((code) => !completedImportCodes.has(code));
}
