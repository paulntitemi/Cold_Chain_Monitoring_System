import clsx from 'clsx';
import { useUiStore } from '@/store/uiStore';
import { env } from '@/config/env';

export function ConnectionStatus() {
  const ok = useUiStore((s) => s.connectionOk);
  const mode = env.useWebSocket ? 'WS' : 'POLL';
  return (
    <div className="flex items-center gap-2 rounded-sm border border-border bg-bg-card px-3 py-1.5">
      <span
        className={clsx(
          'h-2 w-2 rounded-full',
          ok ? 'bg-green animate-pulse' : 'bg-red',
        )}
      />
      <span className="text-[11px] uppercase tracking-wider text-text-secondary">
        {ok ? 'Live' : 'Disconnected'} · {mode}
      </span>
    </div>
  );
}
