import { create } from 'zustand';
import type { Shipment, RiskLevel } from '@/types/shipment';

interface ShipmentsState {
  shipments: Shipment[];
  setShipments: (next: Shipment[]) => void;
  getById: (id: string) => Shipment | undefined;
}

export const useShipmentsStore = create<ShipmentsState>((set, get) => ({
  shipments: [],
  setShipments: (next) => set({ shipments: next }),
  getById: (id) => get().shipments.find((s) => s.id === id),
}));

export function riskRank(level: RiskLevel): number {
  switch (level) {
    case 'critical':
      return 0;
    case 'high':
      return 1;
    case 'warning':
      return 2;
    case 'safe':
      return 3;
  }
}

export function sortedByRisk(shipments: Shipment[]): Shipment[] {
  return [...shipments].sort((a, b) => {
    const rr = riskRank(a.riskLevel) - riskRank(b.riskLevel);
    if (rr !== 0) return rr;
    return b.riskScore - a.riskScore;
  });
}
