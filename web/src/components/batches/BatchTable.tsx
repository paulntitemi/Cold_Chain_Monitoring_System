import { useState } from 'react';
import toast from 'react-hot-toast';
import { useQueryClient } from '@tanstack/react-query';
import type { VaccineBatch } from '@/types/batch';
import { BatchRow } from './BatchRow';
import { BatchDetailModal } from './BatchDetailModal';
import { api } from '@/lib/apiClient';

const headers = [
  'VVM',
  'BATCH ID',
  'VACCINE',
  'DOSES',
  'TEMP RANGE',
  'EXPIRY',
  'EXCURSION',
  'STATUS',
  'UPDATED',
  'ACTIONS',
];

interface Props {
  batches: VaccineBatch[];
}

export function BatchTable({ batches }: Props) {
  const [openBatchId, setOpenBatchId] = useState<string | null>(null);
  const qc = useQueryClient();

  const openBatch = batches.find((b) => b.batchId === openBatchId);

  const discard = async (b: VaccineBatch) => {
    if (!confirm(`Mark ${b.batchId} as discarded? This cannot be undone.`)) return;
    await api.updateBatch(b.batchId, { status: 'discarded', vvmStatus: 'stage4' });
    toast.success(`${b.batchId} discarded`);
    qc.invalidateQueries({ queryKey: ['batches'] });
  };

  return (
    <>
      <div className="flex-1 overflow-auto rounded-sm border border-border bg-bg-secondary">
        <table className="w-full border-collapse text-sm">
          <thead className="sticky top-0 z-10 bg-bg-secondary">
            <tr className="text-left">
              {headers.map((h) => (
                <th
                  key={h}
                  className="border-b border-border px-2 py-2 text-[10px] font-semibold uppercase tracking-widest text-text-secondary"
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {batches.map((b) => (
              <BatchRow
                key={b.batchId}
                batch={b}
                onOpen={() => setOpenBatchId(b.batchId)}
                onEdit={() => setOpenBatchId(b.batchId)}
                onDiscard={() => discard(b)}
              />
            ))}
            {batches.length === 0 && (
              <tr>
                <td colSpan={headers.length} className="py-8 text-center text-sm text-text-secondary">
                  No batches match your filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {openBatch && (
        <BatchDetailModal batch={openBatch} onClose={() => setOpenBatchId(null)} />
      )}
    </>
  );
}
