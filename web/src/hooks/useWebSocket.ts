import { useEffect, useRef } from 'react';
import { io, type Socket } from 'socket.io-client';
import { useQueryClient } from '@tanstack/react-query';
import { env } from '@/config/env';

/**
 * Phase 2 WebSocket hook — wired but gated behind VITE_USE_WEBSOCKET.
 * When enabled, it receives pushed fleet/alert updates and invalidates
 * the React Query cache so the UI re-reads fresh data without polling.
 *
 * To activate:
 *   1. Set VITE_USE_WEBSOCKET=true in .env
 *   2. Set VITE_WS_ENDPOINT to your API Gateway WebSocket URL
 *   3. Mount <WebSocketBridge /> at the app root (or call useWebSocket()
 *      in App.tsx). Both call sites already exist — no other changes needed.
 */
export function useWebSocket(): Socket | null {
  const ref = useRef<Socket | null>(null);
  const qc = useQueryClient();

  useEffect(() => {
    if (!env.useWebSocket || !env.wsEndpoint) return;

    const socket = io(env.wsEndpoint, {
      transports: ['websocket'],
      reconnectionDelay: 2000,
    });
    ref.current = socket;

    socket.on('fleet:update', () => {
      qc.invalidateQueries({ queryKey: ['fleet'] });
    });
    socket.on('alert:new', () => {
      qc.invalidateQueries({ queryKey: ['alerts'] });
    });
    socket.on('shipment:update', (payload: { id: string }) => {
      qc.invalidateQueries({ queryKey: ['shipment', payload.id] });
    });

    return () => {
      socket.disconnect();
      ref.current = null;
    };
  }, [qc]);

  return ref.current;
}
