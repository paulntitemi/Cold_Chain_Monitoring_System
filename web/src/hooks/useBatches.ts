import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/apiClient';

export function useBatches() {
  return useQuery({
    queryKey: ['batches'],
    queryFn: api.getBatches,
    refetchInterval: 10_000,
  });
}

export function useBatch(id: string | null | undefined) {
  return useQuery({
    queryKey: ['batch', id],
    queryFn: () => api.getBatch(id as string),
    enabled: !!id,
  });
}
