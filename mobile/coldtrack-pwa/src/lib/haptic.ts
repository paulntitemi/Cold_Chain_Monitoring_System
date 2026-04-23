/**
 * Feature-detected navigator.vibrate wrapper. iOS Safari ignores it (no-op),
 * Android Chrome honours it, Samsung Internet honours it. Never throws.
 */

type Pattern = number | readonly number[];

export function vibrate(pattern: Pattern): void {
  if (typeof navigator === 'undefined' || typeof navigator.vibrate !== 'function') return;
  try {
    navigator.vibrate(pattern as number | number[]);
  } catch {
    // ignore
  }
}

export function stopVibration(): void {
  if (typeof navigator === 'undefined' || typeof navigator.vibrate !== 'function') return;
  try {
    navigator.vibrate(0);
  } catch {
    // ignore
  }
}

export const PATTERNS = {
  alert: [200, 100, 200, 100, 600],
  alertLoud: [300, 200, 300, 200, 800],
  warningTick: [150, 60, 150],
  confirm: [40],
  miniTap: [15],
} as const;
