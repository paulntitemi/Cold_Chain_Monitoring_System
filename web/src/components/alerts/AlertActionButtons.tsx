import type { Alert } from '@/types/alert';
import { api } from '@/lib/apiClient';
import { useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';

interface Props {
  alert: Alert;
  riderPhone?: string;
  compact?: boolean;
}

export function AlertActionButtons({ alert, riderPhone, compact }: Props) {
  const qc = useQueryClient();

  const escalate = async () => {
    await api.patchAlert(alert.id, { status: 'escalated' });
    toast.success(`Escalated ${alert.shipmentId}`);
    qc.invalidateQueries({ queryKey: ['alerts'] });
  };

  const resolve = async () => {
    await api.patchAlert(alert.id, {
      status: 'resolved',
      resolvedAt: new Date().toISOString(),
      resolvedBy: 'operator',
      outcome: 'delivered_safe',
    });
    toast.success(`Marked ${alert.shipmentId} resolved`);
    qc.invalidateQueries({ queryKey: ['alerts'] });
  };

  const size = compact ? 'px-2 py-1 text-[11px]' : 'px-3 py-1.5 text-xs';

  return (
    <div className="flex flex-wrap gap-1.5">
      {riderPhone && (
        <a
          href={`tel:${riderPhone}`}
          className={`${size} rounded-sm border border-teal/50 bg-teal/10 text-teal hover:bg-teal/20 transition-colors`}
        >
          📞 Call
        </a>
      )}
      <button
        onClick={escalate}
        className={`${size} rounded-sm border border-red/50 bg-red/10 text-red hover:bg-red/20 transition-colors`}
      >
        Escalate
      </button>
      <button
        onClick={resolve}
        className={`${size} rounded-sm border border-border-bright bg-bg-card text-text-secondary hover:text-text-primary transition-colors`}
      >
        Resolve
      </button>
    </div>
  );
}
