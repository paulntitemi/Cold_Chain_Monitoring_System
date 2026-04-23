import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { api } from '@/lib/apiClient';
import { useTripStore } from '@/store/tripStore';

/**
 * Polls /riders/me/shipment. Interval: 5s foreground, 30s otherwise.
 * Keeps the global trip store in sync so any screen that imports it
 * sees the freshest temp/location without prop drilling.
 */
export function useMyShipment(foreground = true) {
  const setShipment = useTripStore((s) => s.setShipment);

  const query = useQuery({
    queryKey: ['me', 'shipment'],
    queryFn: api.getMyShipment,
    refetchInterval: foreground ? 5_000 : 30_000,
    refetchIntervalInBackground: true,
    staleTime: 2_000,
  });

  useEffect(() => {
    if (query.data !== undefined) setShipment(query.data);
  }, [query.data, setShipment]);

  return query;
}
