export function KpiCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="p-4 bg-zinc-900/50 rounded-lg border border-zinc-800">
      <p className="text-[10px] font-medium text-zinc-500 uppercase tracking-wider">{label}</p>
      <p className="text-2xl font-bold text-zinc-100 mt-1 capitalize">{value}</p>
    </div>
  );
}
