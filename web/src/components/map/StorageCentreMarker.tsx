import { OverlayView } from '@react-google-maps/api';
import type { StorageCentre } from '@/types/storageCentre';

interface Props {
  centre: StorageCentre;
}

export function StorageCentreMarker({ centre }: Props) {
  return (
    <OverlayView
      position={centre.location}
      mapPaneName={OverlayView.OVERLAY_MOUSE_TARGET}
      getPixelPositionOffset={(w, h) => ({ x: -w / 2, y: -h / 2 })}
    >
      <div
        className="flex h-6 w-6 items-center justify-center rounded-sm border border-teal/60 bg-bg-card"
        title={centre.name}
      >
        <svg width="12" height="14" viewBox="0 0 12 14" fill="none">
          <path
            d="M6 1v8m0 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4Z"
            stroke="#00C9A7"
            strokeWidth="1.4"
            strokeLinecap="round"
          />
        </svg>
      </div>
    </OverlayView>
  );
}
