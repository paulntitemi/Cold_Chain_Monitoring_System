/**
 * Web Push subscription lifecycle. Phase 1.5 — wired but optional; iOS
 * Safari gates Push on PWA-install, so we always feature-detect and fall
 * back to polling silently.
 */

import { env } from '@/config/env';

function pushSupported(): boolean {
  return (
    typeof window !== 'undefined' &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window
  );
}

function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4);
  const b64 = (base64 + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(b64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

export async function ensurePushSubscription(): Promise<PushSubscription | null> {
  if (!pushSupported() || !env.enableWebPush) return null;
  if (!env.webPushPublicKey) return null;

  try {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') return null;

    const reg = await navigator.serviceWorker.ready;
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(env.webPushPublicKey),
      });
    }
    return sub;
  } catch {
    return null;
  }
}

export async function unsubscribePush(): Promise<void> {
  if (!pushSupported()) return;
  try {
    const reg = await navigator.serviceWorker.ready;
    const sub = await reg.pushManager.getSubscription();
    if (sub) await sub.unsubscribe();
  } catch {
    // ignore
  }
}
