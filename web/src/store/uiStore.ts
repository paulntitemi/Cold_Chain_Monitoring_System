import { create } from 'zustand';

interface UiState {
  selectedShipmentId: string | null;
  detailPanelOpen: boolean;
  mapLayer: 'roadmap' | 'satellite' | 'terrain';
  showStorageCentres: boolean;
  connectionOk: boolean;
  setSelectedShipment: (id: string | null) => void;
  openDetailPanel: (id: string) => void;
  closeDetailPanel: () => void;
  setMapLayer: (layer: UiState['mapLayer']) => void;
  toggleStorageCentres: () => void;
  setConnectionOk: (ok: boolean) => void;
}

export const useUiStore = create<UiState>((set) => ({
  selectedShipmentId: null,
  detailPanelOpen: false,
  mapLayer: 'roadmap',
  showStorageCentres: true,
  connectionOk: true,

  setSelectedShipment: (id) => set({ selectedShipmentId: id }),
  openDetailPanel: (id) => set({ selectedShipmentId: id, detailPanelOpen: true }),
  closeDetailPanel: () => set({ detailPanelOpen: false }),
  setMapLayer: (mapLayer) => set({ mapLayer }),
  toggleStorageCentres: () =>
    set((s) => ({ showStorageCentres: !s.showStorageCentres })),
  setConnectionOk: (connectionOk) => set({ connectionOk }),
}));
