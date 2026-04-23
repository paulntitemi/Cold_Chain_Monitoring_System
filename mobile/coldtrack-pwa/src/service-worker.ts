/// <reference lib="webworker" />
/* eslint-disable no-restricted-globals */
import { precacheAndRoute, cleanupOutdatedCaches } from 'workbox-precaching';
import { registerRoute } from 'workbox-routing';
import {
  StaleWhileRevalidate,
  NetworkFirst,
  CacheFirst,
} from 'workbox-strategies';
import { BackgroundSyncPlugin } from 'workbox-background-sync';

declare const self: ServiceWorkerGlobalScope;

// Injected at build time by vite-plugin-pwa.
precacheAndRoute(self.__WB_MANIFEST ?? []);
cleanupOutdatedCaches();

// Let the page decide when to SKIP_WAITING.
self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') void self.skipWaiting();
});

// --- Runtime caches ---

// Google Maps tiles — stale-while-revalidate
registerRoute(
  ({ url }) =>
    url.hostname === 'maps.googleapis.com' ||
    url.hostname === 'maps.gstatic.com' ||
    url.hostname === 'mts0.googleapis.com' ||
    url.hostname === 'mts1.googleapis.com',
  new StaleWhileRevalidate({ cacheName: 'gmaps-tiles-v1' }),
);

// Web fonts
registerRoute(
  ({ url }) => url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com',
  new CacheFirst({ cacheName: 'google-fonts-v1' }),
);

// Background-sync queue for rider writes. POST/PATCH requests that fail
// offline get pinned here and retried by the SW when connectivity returns.
const bgSync = new BackgroundSyncPlugin('rider-writes', {
  maxRetentionTime: 24 * 60, // minutes
});

registerRoute(
  ({ url }) =>
    /\/api\/.*$/.test(url.pathname) || /execute-api.*\.amazonaws\.com$/.test(url.hostname),
  async ({ event }) => {
    // If the network request fails, the bgSync plugin queues it for replay.
    const response = await fetch((event as FetchEvent).request.clone());
    return response;
  },
  'POST',
);

registerRoute(
  ({ url }) => /\/api\/.*$/.test(url.pathname),
  new NetworkFirst({
    cacheName: 'api-reads-v1',
    networkTimeoutSeconds: 5,
    plugins: [bgSync],
  }),
  'GET',
);

// --- Push ---

self.addEventListener('push', (event) => {
  if (!event.data) return;
  let payload: { title: string; body: string; url?: string } = {
    title: 'ColdTrack Alert',
    body: 'New alert from dispatch',
    url: '/alert',
  };
  try {
    payload = { ...payload, ...event.data.json() };
  } catch {
    // plain text body
  }

  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: '/icons/icon-192.png',
      badge: '/icons/icon-192.png',
      vibrate: [300, 200, 300, 200, 800],
      tag: 'coldtrack-alert',
      requireInteraction: true,
      data: { url: payload.url ?? '/alert' },
    } as NotificationOptions),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data as { url?: string })?.url ?? '/alert';
  event.waitUntil(
    (async () => {
      const allClients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of allClients) {
        if ('focus' in client) {
          await client.focus();
          if ('navigate' in client) await (client as WindowClient).navigate(url);
          return;
        }
      }
      await self.clients.openWindow(url);
    })(),
  );
});
