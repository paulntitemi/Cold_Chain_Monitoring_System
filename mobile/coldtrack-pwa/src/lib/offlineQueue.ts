/**
 * IndexedDB-backed write queue. Position pings, handoffs, custody events
 * all land here first, then get drained on `online` (or when the service
 * worker fires a background-sync event with tag "rider-writes").
 */

import { openDB, type IDBPDatabase } from 'idb';

export type QueueItemMethod = 'POST' | 'PATCH' | 'PUT';

export interface QueueItem {
  id: string;
  method: QueueItemMethod;
  path: string;
  body: unknown;
  enqueuedAt: number;
  attempts: number;
  lastError?: string;
}

const DB_NAME = 'coldtrack-rider';
const STORE = 'writes';
const DB_VERSION = 1;

let dbPromise: Promise<IDBPDatabase> | null = null;

function getDb() {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        if (!db.objectStoreNames.contains(STORE)) {
          db.createObjectStore(STORE, { keyPath: 'id' });
        }
      },
    });
  }
  return dbPromise;
}

export async function enqueueWrite(
  method: QueueItemMethod,
  path: string,
  body: unknown,
): Promise<QueueItem> {
  const db = await getDb();
  const item: QueueItem = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    method,
    path,
    body,
    enqueuedAt: Date.now(),
    attempts: 0,
  };
  await db.put(STORE, item);
  await requestBackgroundSync();
  return item;
}

export async function peekQueue(): Promise<QueueItem[]> {
  const db = await getDb();
  return db.getAll(STORE);
}

export async function removeFromQueue(id: string): Promise<void> {
  const db = await getDb();
  await db.delete(STORE, id);
}

export async function updateQueueItem(item: QueueItem): Promise<void> {
  const db = await getDb();
  await db.put(STORE, item);
}

async function requestBackgroundSync(): Promise<void> {
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;
  try {
    const reg = await navigator.serviceWorker.ready;
    const syncManager = (reg as ServiceWorkerRegistration & {
      sync?: { register(tag: string): Promise<void> };
    }).sync;
    if (syncManager) await syncManager.register('rider-writes');
  } catch {
    // ignore — online event handler will drain
  }
}

export type DrainHandler = (item: QueueItem) => Promise<void>;

/**
 * Iterate the queue, calling `handler` on each item. Items that throw are
 * kept in the queue with attempt count incremented; items that succeed are
 * removed. The caller decides how to handle repeated failures.
 */
export async function drainQueue(handler: DrainHandler): Promise<{
  processed: number;
  failed: number;
}> {
  const items = await peekQueue();
  let processed = 0;
  let failed = 0;

  for (const item of items) {
    try {
      await handler(item);
      await removeFromQueue(item.id);
      processed++;
    } catch (err) {
      failed++;
      await updateQueueItem({
        ...item,
        attempts: item.attempts + 1,
        lastError: err instanceof Error ? err.message : String(err),
      });
    }
  }
  return { processed, failed };
}
