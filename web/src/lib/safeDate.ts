import { format, formatDistanceToNow, type FormatOptions } from 'date-fns';

/**
 * Tolerant date helpers. date-fns throws RangeError on Invalid Date, which
 * crashes whatever React tree they're rendered in. Backend rows from AWS
 * sometimes have empty/missing date fields; mock-created rows occasionally
 * have inconsistent shapes too. These wrappers degrade gracefully so a
 * single bad row never takes the whole view down.
 */

export function safeDate(s: string | undefined | null): Date | null {
  if (!s) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function safeFormat(
  s: string | undefined | null,
  fmt: string,
  fallback = '—',
  options?: FormatOptions,
): string {
  const d = safeDate(s);
  return d ? format(d, fmt, options) : fallback;
}

export function safeDistance(
  s: string | undefined | null,
  fallback = '—',
): string {
  const d = safeDate(s);
  return d ? formatDistanceToNow(d, { addSuffix: true }) : fallback;
}
