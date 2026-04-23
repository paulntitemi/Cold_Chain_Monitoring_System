import { create } from 'zustand';
import type { Rider } from '@/types/rider';

interface AuthState {
  rider: Rider | null;
  loggedIn: boolean;
  setRider: (r: Rider | null) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  rider: null,
  loggedIn: false,
  setRider: (r) => set({ rider: r, loggedIn: !!r }),
  logout: () => set({ rider: null, loggedIn: false }),
}));
