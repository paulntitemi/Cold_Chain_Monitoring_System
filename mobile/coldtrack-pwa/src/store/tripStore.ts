import { create } from 'zustand';
import type { Shipment } from '@/types/shipment';

interface TripState {
  shipment: Shipment | null;
  manifestVerifiedBatchIds: Set<string>;
  setShipment: (s: Shipment | null) => void;
  markBatchVerified: (batchId: string) => void;
  resetManifest: () => void;
  clear: () => void;
}

export const useTripStore = create<TripState>((set) => ({
  shipment: null,
  manifestVerifiedBatchIds: new Set(),
  setShipment: (s) => set({ shipment: s }),
  markBatchVerified: (batchId) =>
    set((state) => {
      const next = new Set(state.manifestVerifiedBatchIds);
      next.add(batchId);
      return { manifestVerifiedBatchIds: next };
    }),
  resetManifest: () => set({ manifestVerifiedBatchIds: new Set() }),
  clear: () => set({ shipment: null, manifestVerifiedBatchIds: new Set() }),
}));
