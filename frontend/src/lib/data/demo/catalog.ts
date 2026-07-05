import type {
  Customer,
  Distributor,
  HierarchyNode,
  NamedEntity,
  Product,
  SalesRep,
} from "@/types/domain";
import type { FilterOptions } from "@/types/reports";
import { createSeededRandom } from "./random";

export const DEMO_DISTRIBUTORS: Distributor[] = [
  { id: "dist-1", code: "DIST001", name: "Distribuidora Alfa", cnpj: "11222333000181", city: "São Paulo", state: "SP", status: "active" },
  { id: "dist-2", code: "DIST002", name: "Distribuidora Beta", cnpj: "22333444000172", city: "Campinas", state: "SP", status: "active" },
  { id: "dist-3", code: "DIST003", name: "Distribuidora Gama", cnpj: "33444555000163", city: "Curitiba", state: "PR", status: "inactive" },
];

export const DEMO_CHANNELS: NamedEntity[] = [
  "Açougue", "Padaria", "Restaurante", "Até 4 Check",
  "Até 10 Check", "Acima 10 Check", "Confeitaria", "Conveniência",
].map((name, index) => ({ id: `channel-${index + 1}`, name, status: "active" }));

export const DEMO_CLUSTERS: NamedEntity[] = ["Ouro", "Prata", "Bronze"].map(
  (name, index) => ({ id: `cluster-${index + 1}`, name, status: "active" }),
);

interface CategorySpec {
  name: string;
  subcategories: { name: string; products: string[] }[];
}

const CATEGORY_SPECS: CategorySpec[] = [
  {
    name: "Snacks de Batatas",
    subcategories: [
      { name: "Lisa", products: ["LISA 36/45G"] },
      { name: "Ondulada", products: ["ONDULADA 14/90G", "ONDULADA 36/45G"] },
    ],
  },
  {
    name: "Yok Extrusados",
    subcategories: [
      { name: "Sabores", products: ["CEBOLA CX 24/54G", "PRES 30/54G", "PRES 16/153G"] },
    ],
  },
  {
    name: "Popcorn Microondas",
    subcategories: [
      { name: "Tradicional", products: ["SAL 36/100G", "CAR CX 30/160G"] },
    ],
  },
  {
    name: "Batata Palha",
    subcategories: [
      { name: "Extrafina", products: ["EXTRAFINA 20X100G", "EXTRAFINA 24X140G"] },
      { name: "Clássica", products: ["CLÁSSICA 20X100G", "CLÁSSICA 12X500G"] },
    ],
  },
];

function buildProductTree(): { tree: HierarchyNode[]; products: Product[] } {
  const products: Product[] = [];
  let productIndex = 0;

  const macro: HierarchyNode = {
    id: "macro-1",
    parentId: null,
    level: "macro_category",
    name: "Alimentos",
    status: "active",
    children: CATEGORY_SPECS.map((category, categoryIndex) => ({
      id: `cat-${categoryIndex + 1}`,
      parentId: "macro-1",
      level: "category" as const,
      name: category.name,
      status: "active" as const,
      children: category.subcategories.map((subcategory, subIndex) => {
        const subId = `sub-${categoryIndex + 1}-${subIndex + 1}`;
        subcategory.products.forEach((productName) => {
          productIndex += 1;
          products.push({
            id: `prod-${productIndex}`,
            ean: `78910001000${String(productIndex).padStart(2, "0")}`,
            skuCode: `SKU-${String(productIndex).padStart(3, "0")}`,
            name: productName,
            subcategoryName: subcategory.name,
            categoryName: category.name,
            status: "active",
          });
        });
        return {
          id: subId,
          parentId: `cat-${categoryIndex + 1}`,
          level: "subcategory" as const,
          name: subcategory.name,
          status: "active" as const,
          children: [],
        };
      }),
    })),
  };

  return { tree: [macro], products };
}

const productTree = buildProductTree();

export const DEMO_PRODUCT_TREE: HierarchyNode[] = productTree.tree;
export const DEMO_PRODUCTS: Product[] = productTree.products;

const SELLER_COUNT = 9;
const SELLERS_PER_SUPERVISOR = 3;

export const DEMO_SUPERVISORS: SalesRep[] = Array.from({ length: 3 }, (_, index) => ({
  id: `sup-${index + 1}`,
  name: `Supervisor ${index + 1}`,
  role: "supervisor",
  supervisorId: null,
  status: "active",
}));

export const DEMO_SELLERS: SalesRep[] = Array.from({ length: SELLER_COUNT }, (_, index) => ({
  id: `seller-${index + 1}`,
  name: `Vendedor ${index + 1}`,
  role: "seller",
  supervisorId: `sup-${Math.floor(index / SELLERS_PER_SUPERVISOR) + 1}`,
  status: index === SELLER_COUNT - 1 ? "inactive" : "active",
}));

const CITY_POOL = [
  { city: "São Paulo", state: "SP" },
  { city: "Campinas", state: "SP" },
  { city: "Santos", state: "SP" },
  { city: "Curitiba", state: "PR" },
  { city: "Londrina", state: "PR" },
];

const CUSTOMER_COUNT = 40;

export const DEMO_CUSTOMERS: Customer[] = (() => {
  const random = createSeededRandom(42);
  return Array.from({ length: CUSTOMER_COUNT }, (_, index) => {
    const location = CITY_POOL[index % CITY_POOL.length];
    return {
      id: `cust-${index + 1}`,
      cnpj: String(10000000000100 + index * 37).padStart(14, "0"),
      legalName: `Cliente ${String(index + 1).padStart(3, "0")} Comércio de Alimentos Ltda`,
      district: `Bairro ${(index % 8) + 1}`,
      city: location.city,
      state: location.state,
      zipCode: String(1000000 + index * 137).padStart(8, "0"),
      channelName: DEMO_CHANNELS[index % DEMO_CHANNELS.length].name,
      clusterName: DEMO_CLUSTERS[index % DEMO_CLUSTERS.length].name,
      salesRepName: DEMO_SELLERS[index % DEMO_SELLERS.length].name,
      status: random() < 0.9 ? "active" : "inactive",
    };
  });
})();

export const DEMO_FILTER_OPTIONS: FilterOptions = {
  distributors: DEMO_DISTRIBUTORS.map(({ id, name }) => ({ id, name })),
  categories: DEMO_PRODUCT_TREE[0].children.map(({ id, name }) => ({ id, name })),
  subcategories: DEMO_PRODUCT_TREE[0].children.flatMap((category) =>
    category.children.map(({ id, name }) => ({ id, name })),
  ),
  products: DEMO_PRODUCTS.map(({ id, name }) => ({ id, name })),
  channels: DEMO_CHANNELS.map(({ id, name }) => ({ id, name })),
  clusters: DEMO_CLUSTERS.map(({ id, name }) => ({ id, name })),
  sellers: DEMO_SELLERS.map(({ id, name }) => ({ id, name })),
  supervisors: DEMO_SUPERVISORS.map(({ id, name }) => ({ id, name })),
};
