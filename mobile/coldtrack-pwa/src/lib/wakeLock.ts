/**
 * Screen Wake Lock wrapper. Keeps the phone screen lit while the rider is on
 * a live trip / alert screen. Re-requests on visibility change because the
 * browser releases the lock on tab-hide.
 */

type WakeLockHandle = {
  release(): Promise<void>;
};

let sentinel: WakeLockSentinel | null = null;
let active = false;

function supported(): boolean {
  return typeof navigator !== 'undefined' && 'wakeLock' in navigator;
}

async function acquire(): Promise<void> {
  if (!supported()) return;
  try {
    const nav = navigator as Navigator & { wakeLock: { request(type: 'screen'): Promise<WakeLockSentinel> } };
    sentinel = await nav.wakeLock.request('screen');
    sentinel.addEventListener('release', () => {
      sentinel = null;
    });
  } catch {
    sentinel = null;
  }
}

function onVisibility() {
  if (active && document.visibilityState === 'visible' && !sentinel) {
    void acquire();
  }
}

export async function acquireWakeLock(): Promise<WakeLockHandle> {
  active = true;
  await acquire();
  document.addEventListener('visibilitychange', onVisibility);
  return {
    async release() {
      active = false;
      document.removeEventListener('visibilitychange', onVisibility);
      if (sentinel) {
        try {
          await sentinel.release();
        } catch {
          // ignore
        }
      }
      sentinel = null;
    },
  };
}
