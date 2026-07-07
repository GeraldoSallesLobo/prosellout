"use client";

import { ChevronDown, ChevronRight, Pencil } from "lucide-react";
import { useState } from "react";
import clsx from "clsx";
import { StatusBadge } from "@/components/ui/badge";

export interface TreeNode {
  id: string;
  name: string;
  isActive: boolean;
  levelLabel?: string;
  children: TreeNode[];
}

interface TreeViewProps {
  nodes: TreeNode[];
  onEdit?: (node: TreeNode) => void;
}

function TreeRow({
  node,
  depth,
  onEdit,
}: {
  node: TreeNode;
  depth: number;
  onEdit?: (node: TreeNode) => void;
}) {
  const [isExpanded, setIsExpanded] = useState(true);
  const hasChildren = node.children.length > 0;

  return (
    <>
      <div
        className="group flex items-center gap-2 border-b border-line/50 py-2 pr-3 transition-colors hover:bg-text1/[0.03]"
        style={{ paddingLeft: `${depth * 22 + 8}px` }}
      >
        <button
          type="button"
          onClick={() => setIsExpanded((current) => !current)}
          className={clsx(
            "rounded p-0.5 text-text2 hover:text-text1",
            !hasChildren && "invisible",
          )}
          aria-label={isExpanded ? "Recolher" : "Expandir"}
        >
          {isExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
        </button>
        <span className="text-[13px] text-text1">{node.name}</span>
        {node.levelLabel ? (
          <span className="rounded bg-bg3 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-text2">
            {node.levelLabel}
          </span>
        ) : null}
        <span className="ml-auto flex items-center gap-2">
          <StatusBadge isActive={node.isActive} />
          {onEdit ? (
            <button
              type="button"
              onClick={() => onEdit(node)}
              className="rounded p-1 text-text2 opacity-0 transition-opacity hover:text-blue group-hover:opacity-100"
              aria-label={`Editar ${node.name}`}
            >
              <Pencil size={13} />
            </button>
          ) : null}
        </span>
      </div>
      {isExpanded
        ? node.children.map((child) => (
            <TreeRow key={child.id} node={child} depth={depth + 1} onEdit={onEdit} />
          ))
        : null}
    </>
  );
}

export function TreeView({ nodes, onEdit }: TreeViewProps) {
  return (
    <div className="card overflow-hidden">
      {nodes.map((node) => (
        <TreeRow key={node.id} node={node} depth={0} onEdit={onEdit} />
      ))}
      {nodes.length === 0 ? (
        <div className="px-4 py-10 text-center text-sm text-text2">
          Nenhum registro encontrado
        </div>
      ) : null}
    </div>
  );
}
