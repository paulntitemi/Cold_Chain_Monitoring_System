import { OverlayView } from '@react-google-maps/api';
import clsx from 'clsx';
import type { Shipment } from '@/types/shipment';

interface Props {
  shipment: Shipment;
  /** Pre-computed (smoothed) screen position. Must be the same value used for
   *  the route polyline so the circle stays exactly on the line. */
  position: { lat: number; lng: number };
  selected?: boolean;
  onClick: () => void;
}

function initials(name: string): string {
  return name
    .split(' ')
    .map((p) => p[0]?.toUpperCase() ?? '')
    .slice(0, 2)
    .join('');
}

const ringColor: Record<Shipment['riskLevel'], string> = {
  safe: '#10B981',
  warning: '#F59E0B',
  high: '#EF4444',
  critical: '#EF4444',
};

export function RiderMarker({ shipment, position, selected, onClick }: Props) {
  const color = ringColor[shipment.riskLevel];
  return (
    <OverlayView
      position={position}
      mapPaneName={OverlayView.OVERLAY_MOUSE_TARGET}
      getPixelPositionOffset={(w, h) => ({ x: -w / 2, y: -h / 2 })}
    >
      <button
        onClick={onClick}
        className={clsx(
          'relative flex h-10 w-10 items-center justify-center rounded-full',
          'bg-bg-card font-display text-xs font-bold text-text-primary',
          'border-2 hover:scale-110 transition-transform',
          selected && 'ring-2 ring-teal ring-offset-2 ring-offset-bg-primary',
        )}
        style={{ borderColor: color }}
        title={`${shipment.id} — ${shipment.riderName}`}
      >
        {(shipment.riskLevel === 'critical' || shipment.riskLevel === 'high') && (
          <>
            <span
              className="absolute inset-0 rounded-full animate-radiate"
              style={{ background: `${color}33`, border: `2px solid ${color}` }}
            />
            {shipment.riskLevel === 'critical' && (
              <span
                className="absolute inset-0 rounded-full animate-radiate"
                style={{
                  background: `${color}22`,
                  border: `2px solid ${color}`,
                  animationDelay: '0.8s',
                }}
              />
            )}
          </>
        )}
        <span className="relative">{initials(shipment.riderName)}</span>
      </button>
    </OverlayView>
  );
}
