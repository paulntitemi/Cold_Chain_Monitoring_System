import { create } from 'zustand';
import type { Alert } from '@/types/alert';

interface AlertsState {
  alerts: Alert[];
  seenIds: Set<string>;
  acknowledgedAutoEscalations: Set<string>;
  setAlerts: (alerts: Alert[]) => void;
  markSeen: (id: string) => void;
  acknowledgeAutoEscalation: (id: string) => void;
  unreadCount: () => number;
}

export const useAlertsStore = create<AlertsState>((set, get) => ({
  alerts: [],
  seenIds: new Set(),
  acknowledgedAutoEscalations: new Set(),

  setAlerts: (alerts) => set({ alerts }),

  markSeen: (id) => {
    const next = new Set(get().seenIds);
    next.add(id);
    set({ seenIds: next });
  },

  acknowledgeAutoEscalation: (id) => {
    const next = new Set(get().acknowledgedAutoEscalations);
    next.add(id);
    set({ acknowledgedAutoEscalations: next });
  },

  unreadCount: () => {
    const { alerts, seenIds } = get();
    return alerts.filter((a) => a.status === 'active' && !seenIds.has(a.id)).length;
  },
}));
