export type EntityStatus = "active" | "inactive";

export interface Distributor {
  id: string;
  code: string;
  name: string;
  cnpj: string | null;
  city: string | null;
  state: string | null;
  status: EntityStatus;
}

export interface NamedEntity {
  id: string;
  name: string;
  status: EntityStatus;
}

export type HierarchyLevel = "macro_category" | "category" | "subcategory";

export interface HierarchyNode {
  id: string;
  parentId: string | null;
  level: HierarchyLevel;
  name: string;
  status: EntityStatus;
  children: HierarchyNode[];
}

export type SalesRole = "supervisor" | "seller";

export interface SalesRep {
  id: string;
  name: string;
  role: SalesRole;
  supervisorId: string | null;
  status: EntityStatus;
}

export interface Customer {
  id: string;
  cnpj: string;
  legalName: string;
  district: string | null;
  city: string | null;
  state: string | null;
  zipCode: string | null;
  channelName: string | null;
  clusterName: string | null;
  salesRepName: string | null;
  status: EntityStatus;
}

export interface Product {
  id: string;
  ean: string;
  skuCode: string | null;
  name: string;
  subcategoryName: string | null;
  categoryName: string | null;
  status: EntityStatus;
}

export type ImportStatus =
  | "pending"
  | "validating"
  | "processing"
  | "completed"
  | "completed_with_errors"
  | "failed";

export interface FileImport {
  id: string;
  fileName: string;
  sheetName: string | null;
  typeName: string;
  status: ImportStatus;
  totalRecords: number;
  processedRecords: number;
  errorCount: number;
  createdAt: string;
  importedBy: string | null;
}

export interface FileImportLog {
  id: number;
  lineNumber: number | null;
  level: "info" | "warning" | "error";
  message: string;
  createdAt: string;
}

export interface FileTypeConfig {
  id: string;
  code: string;
  name: string;
  targetTable: string;
  processingRoutine: string;
  fileFormat: string;
  origin: string;
  status: EntityStatus;
}

export interface SellOutRow {
  id: number;
  distributorName: string;
  customerName: string;
  ean: string;
  productName: string;
  invoiceDate: string;
  quantity: number;
  grossValue: number;
}

export interface SellInRow {
  id: number;
  distributorName: string;
  ean: string;
  productName: string;
  invoiceDate: string;
  quantity: number;
  grossValue: number;
}

export interface StockRow {
  id: string;
  distributorName: string;
  ean: string;
  productName: string;
  snapshotDate: string;
  quantity: number;
  grossValue: number;
}

export interface TargetRow {
  id: number;
  customerName: string;
  ean: string;
  productName: string;
  targetDate: string;
  quantity: number;
  grossValue: number;
}

export interface Paginated<T> {
  rows: T[];
  total: number;
}
