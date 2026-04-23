import { clsx } from 'clsx';
import type { RouteInfo } from './TripMap';

interface Props {
  info: RouteInfo | null;
  onClose?(): void;
  compact?: boolean;
}

const maneuverArrows: Record<string, string> = {
  'turn-left': '←',
  'turn-right': '→',
  'turn-slight-left': '↖',
  'turn-slight-right': '↗',
  'turn-sharp-left': '⟲',
  'turn-sharp-right': '⟳',
  'uturn-left': '⤸',
  'uturn-right': '⤹',
  'roundabout-left': '↺',
  'roundabout-right': '↻',
  'fork-left': '⤴',
  'fork-right': '⤵',
  'merge': '⇉',
  'ramp-left': '↖',
  'ramp-right': '↗',
  'straight': '↑',
  'keep-left': '↖',
  'keep-right': '↗',
};

function arrow(maneuver: string): string {
  return maneuverArrows[maneuver] ?? '↑';
}

function formatDistance(meters: number): string {
  if (meters < 100) return `${Math.round(meters / 10) * 10} m`;
  if (meters < 1000) return `${Math.round(meters / 50) * 50} m`;
  return `${(meters / 1000).toFixed(1)} km`;
}

/**
 * Turn-by-turn instruction overlay shown when the rider is in navigation
 * mode. Reads the current step from the Directions response and renders
 * the next maneuver + distance. Not spoken (browsers don't do spoken
 * turn-by-turn) but visually identical to Google Maps' nav header.
 */
export function InstructionCard({ info, onClose, compact }: Props) {
  if (!info || info.currentStepIndex < 0 || info.steps.length === 0) {
    return null;
  }

  const step = info.steps[info.currentStepIndex];
  const upcomingStep = info.steps[info.currentStepIndex + 1];
  const distance = formatDistance(info.distanceToNextManeuverM);

  if (info.arrived) {
    return (
      <div className="border border-teal bg-teal/15 text-teal p-3 rounded-sm flex items-center gap-3">
        <div className="text-3xl font-display font-bold">✓</div>
        <div className="flex-1">
          <div className="font-display font-semibold text-lg">Arrived</div>
          <div className="font-mono text-[11px] uppercase tracking-wider text-teal/80">
            Complete the handoff below
          </div>
        </div>
      </div>
    );
  }

  return (
    <div
      className={clsx(
        'border border-teal/40 bg-bg-secondary/95 backdrop-blur rounded-sm flex items-stretch gap-3 shadow-lg',
        compact ? 'p-2' : 'p-3',
      )}
      role="status"
      aria-live="polite"
    >
      <div
        className={clsx(
          'flex items-center justify-center rounded-sm bg-teal/15 text-teal font-display font-bold',
          compact ? 'w-12 text-2xl' : 'w-16 text-4xl',
        )}
        aria-hidden
      >
        {arrow(step.maneuver)}
      </div>
      <div className="flex-1 min-w-0">
        <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-teal">
          In {distance}
        </div>
        <div
          className={clsx(
            'font-body font-medium text-text-primary leading-tight mt-0.5',
            compact ? 'text-sm' : 'text-base',
          )}
        >
          {step.instructionText}
        </div>
        {upcomingStep && !compact && (
          <div className="font-mono text-[10px] uppercase tracking-wider text-text-secondary mt-1 truncate">
            Then · {arrow(upcomingStep.maneuver)} {upcomingStep.instructionText}
          </div>
        )}
      </div>
      {onClose && (
        <button
          type="button"
          onClick={onClose}
          aria-label="Exit navigation"
          className="text-text-secondary font-mono text-xs uppercase tracking-wider px-2 self-start"
        >
          ✕
        </button>
      )}
    </div>
  );
}
