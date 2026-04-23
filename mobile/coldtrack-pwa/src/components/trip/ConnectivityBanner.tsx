import { useOnline } from '@/hooks/useOnline';

export function ConnectivityBanner() {
  const online = useOnline();
  if (online) return null;
  return (
    <div
      className="w-full bg-amber/15 border-b border-amber/40 text-amber text-center text-xs font-mono uppercase tracking-wider py-1.5 animate-pulse-amber rounded-sm"
      role="status"
    >
      Offline — pings and handoffs will sync when signal returns
    </div>
  );
}
