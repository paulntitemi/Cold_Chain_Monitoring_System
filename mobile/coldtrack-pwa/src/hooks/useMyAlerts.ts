import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { api } from '@/lib/apiClient';
import { useAlertStore } from '@/store/alertStore';

/**
 * Polls /riders/me/alerts. When a new active alert first appears, stages it
 * in alertStore. The AlertRouter side-effect picks it up and navigates to
 * /alert — no prop drilling required.
 */
export function useMyAlerts(foreground = true) {
  const setActiveAlert = useAlertStore((s) => s.setActiveAlert);
  const seen = useAlertStore((s) => s.seenAlertIds);

  const query = useQuery({
    queryKey: ['me', 'alerts'],
    queryFn: api.getMyAlerts,
    refetchInterval: foreground ? 5_000 : 15_000,
    refetchIntervalInBackground: true,
    staleTime: 2_000,
  });

  useEffect(() => {
    if (!query.data) return;
    const fresh = query.data.find((a) => a.status === 'active' && !seen.has(a.id));
    if (fresh) setActiveAlert(fresh);
    else if (query.data.length === 0) setActiveAlert(null);
  }, [query.data, seen, setActiveAlert]);

  return query;
}
