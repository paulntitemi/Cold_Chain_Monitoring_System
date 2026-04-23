import { create } from 'zustand';
import type { Alert } from '@/types/alert';

interface AlertState {
  /**
   * The alert id of the most recent active alert the user has been
   * navigated to — prevents the poller from bouncing them back into the
   * alert screen after they've responded.
   */
  seenAlertIds: Set<string>;
  activeAlert: Alert | null;
  setActiveAlert: (a: Alert | null) => void;
  markSeen: (id: string) => void;
  clear: () => void;
}

export const useAlertStore = create<AlertState>((set) => ({
  seenAlertIds: new Set(),
  activeAlert: null,
  setActiveAlert: (a) => set({ activeAlert: a }),
  markSeen: (id) =>
    set((s) => {
      const next = new Set(s.seenAlertIds);
      next.add(id);
      return { seenAlertIds: next };
    }),
  clear: () => set({ activeAlert: null, seenAlertIds: new Set() }),
}));
