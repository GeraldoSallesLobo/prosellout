"use client";

import { usePathname } from "next/navigation";
import { findBreadcrumb } from "@/lib/navigation";

export function Breadcrumb() {
  const pathname = usePathname();
  const trail = findBreadcrumb(pathname);
  if (!trail) return null;

  return (
    <div className="text-[13px] text-text2">
      {trail.group} <span className="mx-1 text-text2/60">›</span>
      <span className="font-semibold text-text1">{trail.page}</span>
    </div>
  );
}
