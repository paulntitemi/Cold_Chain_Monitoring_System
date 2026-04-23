import { useMemo, useState } from 'react';
import clsx from 'clsx';
import { differenceInDays } from 'date-fns';
import { useBatches } from '@/hooks/useBatches';
import { BatchTable } from '@/components/batches/BatchTable';
import { BatchRegistrationModal } from '@/components/batches/BatchRegistrationModal';

type Filter = 'all' | 'in_transit' | 'in_storage' | 'delivered' | 'discarded' | 'expiring';
type SortKey = 'batchId' | 'expiry' | 'excursion' | 'vvm';

const filters: Array<{ id: Filter; label: string }> = [
  { id: 'all', label: 'All' },
  { id: 'in_transit', label: 'In Transit' },
  { id: 'in_storage', label: 'In Storage' },
  { id: 'delivered', label: 'Delivered' },
  { id: 'discarded', label: 'Discarded' },
  { id: 'expiring', label: 'Expiring Soon' },
];

export function BatchRegistry() {
  const { data, isLoading } = useBatches();
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [sort, setSort] = useState<SortKey>('expiry');
  const [registerOpen, setRegisterOpen] = useState(false);

  const filtered = useMemo(() => {
    const src = data ?? [];
    const q = query.trim().toLowerCase();
    return src
      .filter((b) => {
        if (q) {
          const hay = `${b.batchId} ${b.vaccineType} ${b.manufacturer}`.toLowerCase();
          if (!hay.includes(q)) return false;
        }
        switch (filter) {
          case 'all':
            return true;
          case 'in_transit':
            return b.status === 'in_transit';
          case 'in_storage':
            return b.status === 'in_storage';
          case 'delivered':
            return b.status === 'delivered';
          case 'discarded':
            return b.status === 'discarded';
          case 'expiring':
            return differenceInDays(new Date(b.expiryDate), new Date()) < 90;
        }
      })
      .sort((a, b) => {
        switch (sort) {
          case 'batchId':
            return a.batchId.localeCompare(b.batchId);
          case 'expiry':
            return +new Date(a.expiryDate) - +new Date(b.expiryDate);
          case 'excursion':
            return b.totalExcursionMinutes - a.totalExcursionMinutes;
          case 'vvm':
            return a.vvmStatus.localeCompare(b.vvmStatus);
        }
      });
  }, [data, query, filter, sort]);

  return (
    <div className="flex flex-1 flex-col min-h-0 p-5 gap-4 bg-bg-primary">
      <div className="flex flex-wrap items-center gap-3">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search batch ID, vaccine, manufacturer…"
          className="w-80 rounded-sm border border-border bg-bg-card px-3 py-1.5 text-sm text-text-primary focus:border-teal focus:outline-none"
        />

        <div className="flex gap-1">
          {filters.map((f) => (
            <button
              key={f.id}
              onClick={() => setFilter(f.id)}
              className={clsx(
                'rounded-sm border px-3 py-1 text-[11px] uppercase tracking-widest transition-colors',
                filter === f.id
                  ? 'border-teal/40 bg-teal/10 text-teal'
                  : 'border-border bg-bg-card text-text-secondary hover:text-text-primary',
              )}
            >
              {f.label}
            </button>
          ))}
        </div>

        <label className="flex items-center gap-2 text-[11px] uppercase tracking-widest text-text-secondary">
          Sort
          <select
            value={sort}
            onChange={(e) => setSort(e.target.value as SortKey)}
            className="rounded-sm border border-border bg-bg-card px-2 py-1 text-xs text-text-primary focus:border-teal focus:outline-none"
          >
            <option value="expiry">Expiry Date</option>
            <option value="batchId">Batch ID</option>
            <option value="excursion">Excursion Time</option>
            <option value="vvm">VVM Status</option>
          </select>
        </label>

        <div className="flex-1" />
        <button
          onClick={() => setRegisterOpen(true)}
          className="rounded-sm border border-teal/60 bg-teal/20 px-4 py-1.5 text-xs font-semibold uppercase tracking-widest text-teal hover:bg-teal/30"
        >
          Register New Batch
        </button>
      </div>

      {isLoading ? (
        <div className="flex-1 flex items-center justify-center text-text-secondary">
          Loading batches…
        </div>
      ) : (
        <BatchTable batches={filtered} />
      )}

      {registerOpen && <BatchRegistrationModal onClose={() => setRegisterOpen(false)} />}
    </div>
  );
}
