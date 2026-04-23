import type { ReactNode } from 'react';
import { clsx } from 'clsx';

interface Props {
  children: ReactNode;
  critical?: boolean;
}

/**
 * Full-bleed red takeover container. Pulses the border at the 1.8s cadence
 * the dashboard AlertFeedItem uses — identical keyframe names in tailwind
 * config so the two surfaces flash in sync.
 */
export function AlertOverlay({ children, critical }: Props) {
  return (
    <div
      className={clsx(
        'fixed inset-0 z-50 flex flex-col bg-red-tint border-8 motion-safe:animate-flash',
        critical ? 'border-red animate-pulse-fast' : 'border-red animate-pulse-red',
      )}
      style={{
        paddingTop: 'env(safe-area-inset-top)',
        paddingBottom: 'env(safe-area-inset-bottom)',
      }}
      role="alertdialog"
      aria-live="assertive"
    >
      {children}
    </div>
  );
}
