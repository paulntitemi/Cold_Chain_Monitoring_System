import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/apiClient';

export function useMyAssignments() {
  return useQuery({
    queryKey: ['me', 'assignments'],
    queryFn: api.getMyAssignments,
    refetchInterval: 30_000,
    staleTime: 10_000,
  });
}
