import clsx from "clsx";

export function Skeleton({ className }: { className?: string }) {
  return <div className={clsx("animate-skeleton rounded bg-bg3", className)} />;
}

export function KpiCardSkeleton() {
  return (
    <div className="card space-y-3 p-4">
      <Skeleton className="h-3 w-20" />
      <Skeleton className="h-6 w-28" />
      <Skeleton className="h-3 w-24" />
    </div>
  );
}
