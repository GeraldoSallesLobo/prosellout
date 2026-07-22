"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import clsx from "clsx";
import {
  ArrowDown,
  ArrowUp,
  ChevronLeft,
  ChevronRight,
  ChevronsUpDown,
  Search,
  X,
} from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { matchesSearch, type SearchState } from "@/lib/search";
import { sortByValue, type SortState } from "@/lib/sort";

export type { SortState } from "@/lib/sort";
export type { SearchState } from "@/lib/search";

export type DataTableRowKey = string | number;

export interface DataTableColumn<T> {
  key: string;
  header: string;
  align?: "left" | "right" | "center";
  render: (row: T) => React.ReactNode;
  /**
   * Valor bruto usado na ordenação client-side. Sem ele (e sem
   * `onSortChange` na tabela), a coluna não é ordenável.
   */
  sortValue?: (row: T) => string | number | null;
  /** Desativa a ordenação desta coluna (ex.: coluna de ações). */
  sortable?: boolean;
  /**
   * Valor usado na busca client-side. Quando ausente, usa `sortValue`.
   */
  searchValue?: (row: T) => string | number | null;
  /**
   * Busca: em modo controlado (com `onSearchChange`), apenas colunas com
   * `searchable: true` entram no seletor; em modo local, qualquer coluna
   * com `searchValue`/`sortValue` participa, salvo `searchable: false`.
   */
  searchable?: boolean;
}

interface DataTableProps<T> {
  columns: DataTableColumn<T>[];
  rows: T[];
  rowKey: (row: T) => DataTableRowKey;
  isLoading?: boolean;
  emptyMessage?: string;
  /** Highlights a footer-like row (e.g. TOTAL). Fica fora da ordenação e da paginação. */
  isFooterRow?: (row: T) => boolean;
  /**
   * Paginação controlada (server-side). Quando ausente, o DataTable
   * pagina localmente as linhas recebidas.
   */
  pagination?: {
    page: number;
    pageSize: number;
    total: number;
    onPageChange: (page: number) => void;
    onPageSizeChange?: (pageSize: number) => void;
  };
  /** Ordenação controlada (server-side), usada em conjunto com onSortChange. */
  sort?: SortState | null;
  /** Quando presente, cliques no cabeçalho delegam a ordenação ao chamador. */
  onSortChange?: (sort: SortState | null) => void;
  /** Busca controlada (server-side), usada em conjunto com onSearchChange. */
  search?: SearchState | null;
  /** Quando presente, a busca é delegada ao chamador (com debounce interno). */
  onSearchChange?: (search: SearchState | null) => void;
  pageSizeOptions?: number[];
  rowSelection?: {
    selectedKeys: Set<DataTableRowKey>;
    onSelectedKeysChange: (keys: Set<DataTableRowKey>) => void;
  };
}

const SKELETON_ROW_COUNT = 6;
const DEFAULT_PAGE_SIZE_OPTIONS = [10, 25, 50, 100];
const DEFAULT_PAGE_SIZE = 25;

const ALIGN_STYLES = {
  left: "text-left",
  right: "text-right",
  center: "text-center",
} as const;

const JUSTIFY_STYLES = {
  left: "justify-start",
  right: "justify-end",
  center: "justify-center",
} as const;

function nextSortState(current: SortState | null, key: string): SortState | null {
  if (current?.key !== key) return { key, direction: "asc" };
  return current.direction === "asc" ? { key, direction: "desc" } : null;
}

export function DataTable<T>({
  columns,
  rows,
  rowKey,
  isLoading = false,
  emptyMessage = "Nenhum registro encontrado",
  isFooterRow,
  pagination,
  sort,
  onSortChange,
  search,
  onSearchChange,
  pageSizeOptions,
  rowSelection,
}: DataTableProps<T>) {
  const sizeOptions = pageSizeOptions ?? DEFAULT_PAGE_SIZE_OPTIONS;
  const isSortControlled = Boolean(onSortChange);
  const isSearchControlled = Boolean(onSearchChange);

  const [internalSort, setInternalSort] = useState<SortState | null>(null);
  const [internalPage, setInternalPage] = useState(1);
  const [internalPageSize, setInternalPageSize] = useState(
    sizeOptions.includes(DEFAULT_PAGE_SIZE) ? DEFAULT_PAGE_SIZE : sizeOptions[0],
  );
  const [internalSearch, setInternalSearch] = useState<SearchState | null>(null);
  const [searchKey, setSearchKey] = useState<string | null>(null);
  const [searchInput, setSearchInput] = useState(search?.text ?? "");
  const lastCommittedSearch = useRef(search ? `${search.key}::${search.text}` : "");
  const selectAllRef = useRef<HTMLInputElement>(null);

  const activeSort = isSortControlled ? (sort ?? null) : internalSort;
  const isSelectionEnabled = Boolean(rowSelection);

  const isColumnSearchable = (column: DataTableColumn<T>) =>
    isSearchControlled
      ? column.searchable === true
      : column.searchable !== false && Boolean(column.searchValue ?? column.sortValue);

  const searchableColumns = columns.filter(isColumnSearchable);
  const activeSearchKey =
    searchKey && searchableColumns.some((column) => column.key === searchKey)
      ? searchKey
      : searchableColumns[0]?.key ?? null;

  // Aplica a busca com debounce, tanto no modo controlado quanto no local.
  useEffect(() => {
    const text = searchInput.trim();
    const next = text && activeSearchKey ? { key: activeSearchKey, text } : null;
    const signature = next ? `${next.key}::${next.text}` : "";
    if (signature === lastCommittedSearch.current) return;

    const handle = setTimeout(() => {
      lastCommittedSearch.current = signature;
      if (isSearchControlled) {
        onSearchChange?.(next);
      } else {
        setInternalSearch(next);
        setInternalPage(1);
      }
    }, 350);
    return () => clearTimeout(handle);
  }, [searchInput, activeSearchKey, isSearchControlled, onSearchChange]);

  const isColumnSortable = (column: DataTableColumn<T>) =>
    column.sortable !== false && (isSortControlled || Boolean(column.sortValue));

  const handleSortClick = (column: DataTableColumn<T>) => {
    const next = nextSortState(activeSort, column.key);
    if (isSortControlled) {
      onSortChange?.(next);
    } else {
      setInternalSort(next);
      setInternalPage(1);
    }
  };

  // Linhas de rodapé (ex.: TOTAL) ficam fora de sort/paginação e sempre ao final.
  const bodyRows = useMemo(
    () => (isFooterRow ? rows.filter((row) => !isFooterRow(row)) : rows),
    [rows, isFooterRow],
  );
  const footerRows = useMemo(
    () => (isFooterRow ? rows.filter(isFooterRow) : []),
    [rows, isFooterRow],
  );

  const filteredRows = useMemo(() => {
    if (isSearchControlled || !internalSearch) return bodyRows;
    const column = columns.find((item) => item.key === internalSearch.key);
    const getValue = column?.searchValue ?? column?.sortValue;
    if (!getValue) return bodyRows;
    return bodyRows.filter((row) => matchesSearch(getValue(row), internalSearch.text));
  }, [bodyRows, columns, internalSearch, isSearchControlled]);

  const sortedRows = useMemo(() => {
    if (isSortControlled || !activeSort) return filteredRows;
    const column = columns.find((item) => item.key === activeSort.key);
    return sortByValue(filteredRows, activeSort, column?.sortValue);
  }, [filteredRows, columns, activeSort, isSortControlled]);

  const total = pagination?.total ?? sortedRows.length;
  const pageSize = pagination?.pageSize ?? internalPageSize;
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const page = Math.min(pagination?.page ?? internalPage, totalPages);

  const visibleRows = pagination
    ? sortedRows
    : sortedRows.slice((page - 1) * pageSize, page * pageSize);
  const renderedRows = [...visibleRows, ...footerRows];
  const visibleRowKeys = useMemo(() => visibleRows.map(rowKey), [visibleRows, rowKey]);
  const selectedVisibleCount = rowSelection
    ? visibleRowKeys.filter((key) => rowSelection.selectedKeys.has(key)).length
    : 0;
  const hasVisibleRows = visibleRowKeys.length > 0;
  const isEveryVisibleRowSelected =
    Boolean(rowSelection) && hasVisibleRows && selectedVisibleCount === visibleRowKeys.length;
  const hasPartialVisibleSelection =
    Boolean(rowSelection) && selectedVisibleCount > 0 && !isEveryVisibleRowSelected;

  const handlePageChange = (nextPage: number) => {
    if (pagination) pagination.onPageChange(nextPage);
    else setInternalPage(nextPage);
  };

  const handlePageSizeChange = (nextSize: number) => {
    if (pagination) {
      pagination.onPageSizeChange?.(nextSize);
    } else {
      setInternalPageSize(nextSize);
      setInternalPage(1);
    }
  };

  const showPageSizeSelect = pagination ? Boolean(pagination.onPageSizeChange) : true;
  const showFooterBar = pagination ? true : !isLoading && bodyRows.length > 0;

  const activeSearchColumn = searchableColumns.find(
    (column) => column.key === activeSearchKey,
  );

  useEffect(() => {
    if (!isSearchControlled) return;
    const signature = search ? `${search.key}::${search.text}` : "";
    lastCommittedSearch.current = signature;
    setSearchKey(search?.key ?? null);
    setSearchInput(search?.text ?? "");
  }, [isSearchControlled, search?.key, search?.text]);

  useEffect(() => {
    if (!selectAllRef.current) return;
    selectAllRef.current.indeterminate = hasPartialVisibleSelection;
  }, [hasPartialVisibleSelection]);

  function handleRowSelectionChange(key: DataTableRowKey, isSelected: boolean): void {
    if (!rowSelection) return;
    const nextKeys = new Set(rowSelection.selectedKeys);
    if (isSelected) nextKeys.add(key);
    else nextKeys.delete(key);
    rowSelection.onSelectedKeysChange(nextKeys);
  }

  function handleVisibleSelectionChange(isSelected: boolean): void {
    if (!rowSelection) return;
    const nextKeys = new Set(rowSelection.selectedKeys);
    visibleRowKeys.forEach((key) => {
      if (isSelected) nextKeys.add(key);
      else nextKeys.delete(key);
    });
    rowSelection.onSelectedKeysChange(nextKeys);
  }

  return (
    <div className="card overflow-hidden">
      {searchableColumns.length > 0 ? (
        <div className="flex items-center gap-2 border-b border-line px-3 py-2">
          <Search size={14} className="shrink-0 text-text2" />
          <select
            value={activeSearchKey ?? ""}
            onChange={(event) => setSearchKey(event.target.value)}
            aria-label="Coluna da busca"
            className="rounded-md border border-line bg-bg2 px-2 py-1 text-xs text-text1 outline-none transition-colors hover:border-blue/50 focus:border-blue"
          >
            {searchableColumns.map((column) => (
              <option key={column.key} value={column.key}>
                {column.header}
              </option>
            ))}
          </select>
          <input
            type="text"
            value={searchInput}
            onChange={(event) => setSearchInput(event.target.value)}
            placeholder={
              activeSearchColumn ? `Buscar por ${activeSearchColumn.header}...` : "Buscar..."
            }
            className="min-w-0 flex-1 bg-transparent text-[13px] text-text1 outline-none placeholder:text-text2/60"
          />
          {searchInput ? (
            <button
              type="button"
              onClick={() => setSearchInput("")}
              aria-label="Limpar busca"
              className="shrink-0 rounded-md p-1 text-text2 transition-colors hover:bg-text1/5 hover:text-text1"
            >
              <X size={14} />
            </button>
          ) : null}
        </div>
      ) : null}
      <div className="max-h-[70vh] overflow-auto">
        <table className="w-full text-[13px]">
          <thead className="sticky top-0 z-10 bg-card">
            <tr className="bg-bg3/60">
              {isSelectionEnabled ? (
                <th className="w-10 px-3 py-2.5 shadow-[inset_0_-1px_0_rgb(var(--line))]">
                  <input
                    ref={selectAllRef}
                    type="checkbox"
                    checked={isEveryVisibleRowSelected}
                    disabled={!hasVisibleRows || isLoading}
                    onChange={(event) => handleVisibleSelectionChange(event.target.checked)}
                    aria-label="Selecionar linhas visíveis"
                    className="h-4 w-4 rounded border-line accent-blue"
                  />
                </th>
              ) : null}
              {columns.map((column) => {
                const sortable = isColumnSortable(column);
                const isActive = sortable && activeSort?.key === column.key;
                const align = column.align ?? "left";
                return (
                  <th
                    key={column.key}
                    aria-sort={
                      isActive
                        ? activeSort?.direction === "asc"
                          ? "ascending"
                          : "descending"
                        : undefined
                    }
                    className={clsx(
                      "whitespace-nowrap px-4 py-2.5 text-[11px] font-bold uppercase tracking-wide text-text2",
                      "shadow-[inset_0_-1px_0_rgb(var(--line))]",
                      ALIGN_STYLES[align],
                    )}
                  >
                    {sortable ? (
                      <button
                        type="button"
                        onClick={() => handleSortClick(column)}
                        className={clsx(
                          "inline-flex w-full items-center gap-1 uppercase tracking-wide transition-colors hover:text-text1",
                          JUSTIFY_STYLES[align],
                          isActive && "text-text1",
                        )}
                        aria-label={`Ordenar por ${column.header}`}
                      >
                        {column.header}
                        {isActive ? (
                          activeSort?.direction === "asc" ? (
                            <ArrowUp size={12} className="shrink-0 text-blue" />
                          ) : (
                            <ArrowDown size={12} className="shrink-0 text-blue" />
                          )
                        ) : (
                          <ChevronsUpDown size={12} className="shrink-0 opacity-40" />
                        )}
                      </button>
                    ) : (
                      column.header
                    )}
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody>
            {isLoading
              ? Array.from({ length: SKELETON_ROW_COUNT }).map((_, index) => (
                  <tr key={index} className="border-b border-line/60">
                    {isSelectionEnabled ? (
                      <td className="px-3 py-3">
                        <Skeleton className="h-4 w-4" />
                      </td>
                    ) : null}
                    {columns.map((column) => (
                      <td key={column.key} className="px-4 py-3">
                        <Skeleton className="h-3.5 w-full max-w-32" />
                      </td>
                    ))}
                  </tr>
                ))
              : renderedRows.map((row) => {
                  const isFooter = isFooterRow?.(row) ?? false;
                  const key = rowKey(row);
                  return (
                    <tr
                      key={key}
                      className={clsx(
                        "border-b border-line/60 transition-colors last:border-b-0",
                        isFooter ? "bg-text1/[0.04] font-bold" : "hover:bg-text1/[0.03]",
                      )}
                    >
                      {isSelectionEnabled ? (
                        <td className="px-3 py-2.5">
                          {isFooter ? null : (
                            <input
                              type="checkbox"
                              checked={rowSelection?.selectedKeys.has(key) ?? false}
                              onChange={(event) =>
                                handleRowSelectionChange(key, event.target.checked)
                              }
                              aria-label="Selecionar linha"
                              className="h-4 w-4 rounded border-line accent-blue"
                            />
                          )}
                        </td>
                      ) : null}
                      {columns.map((column) => (
                        <td
                          key={column.key}
                          className={clsx(
                            "whitespace-nowrap px-4 py-2.5 text-text3",
                            ALIGN_STYLES[column.align ?? "left"],
                          )}
                        >
                          {column.render(row)}
                        </td>
                      ))}
                    </tr>
                  );
                })}
            {!isLoading && renderedRows.length === 0 ? (
              <tr>
                <td
                  colSpan={columns.length + (isSelectionEnabled ? 1 : 0)}
                  className="px-4 py-10 text-center text-text2"
                >
                  {emptyMessage}
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>

      {showFooterBar ? (
        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-line px-4 py-2.5 text-xs text-text2">
          <span>
            {total.toLocaleString("pt-BR")} registros · página {page} de {totalPages}
            {rowSelection && rowSelection.selectedKeys.size > 0
              ? ` · ${rowSelection.selectedKeys.size.toLocaleString("pt-BR")} selecionados`
              : ""}
          </span>
          <div className="flex items-center gap-3">
            {showPageSizeSelect ? (
              <label className="flex items-center gap-1.5">
                Itens por página
                <select
                  value={pageSize}
                  onChange={(event) => handlePageSizeChange(Number(event.target.value))}
                  className="rounded-md border border-line bg-bg2 px-2 py-1 text-xs text-text1 outline-none transition-colors hover:border-blue/50 focus:border-blue"
                >
                  {sizeOptions.map((size) => (
                    <option key={size} value={size}>
                      {size}
                    </option>
                  ))}
                </select>
              </label>
            ) : null}
            <div className="flex items-center gap-1">
              <button
                type="button"
                disabled={page <= 1}
                onClick={() => handlePageChange(page - 1)}
                className="rounded-md border border-line p-1.5 transition-colors hover:border-blue/50 disabled:opacity-40"
                aria-label="Página anterior"
              >
                <ChevronLeft size={14} />
              </button>
              <button
                type="button"
                disabled={page >= totalPages}
                onClick={() => handlePageChange(page + 1)}
                className="rounded-md border border-line p-1.5 transition-colors hover:border-blue/50 disabled:opacity-40"
                aria-label="Próxima página"
              >
                <ChevronRight size={14} />
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
