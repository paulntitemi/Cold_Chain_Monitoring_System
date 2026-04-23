import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/apiClient';

export function useShipmentDetail(id: string | null | undefined) {
  return useQuery({
    queryKey: ['shipment', id],
    queryFn: () => api.getShipment(id as string),
    enabled: !!id,
    refetchInterval: id ? 5000 : false,
  });
}
