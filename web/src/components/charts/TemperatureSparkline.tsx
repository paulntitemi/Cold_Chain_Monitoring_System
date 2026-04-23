import type { TemperatureReading } from '@/types/shipment';

interface Props {
  readings: TemperatureReading[];
  minSafe?: number;
  maxSafe?: number;
  width?: number;
  height?: number;
}

/**
 * Pure-SVG sparkline. Recharts is too heavy to instantiate per-row in a
 * table of 20+ rows — SVG keeps the fleet table at 60fps.
 */
export function TemperatureSparkline({
  readings,
  minSafe = 2.0,
  maxSafe = 8.0,
  width = 120,
  height = 30,
}: Props) {
  const slice = readings.slice(-20);
  if (slice.length < 2) {
    return (
      <div
        className="flex items-center justify-center text-[10px] text-text-dim"
        style={{ width, height }}
      >
        no data
      </div>
    );
  }

  const temps = slice.map((r) => r.temperature);
  const min = Math.min(...temps, minSafe - 1);
  const max = Math.max(...temps, maxSafe + 1);
  const range = Math.max(0.1, max - min);
  const stepX = width / (slice.length - 1);
  const y = (t: number) => height - ((t - min) / range) * height;

  const pts = slice.map((r, i) => `${i * stepX},${y(r.temperature).toFixed(2)}`).join(' ');

  // Safe-range band.
  const bandY1 = y(maxSafe);
  const bandY2 = y(minSafe);
  const breached = slice.some((r) => r.temperature < minSafe || r.temperature > maxSafe);

  return (
    <svg width={width} height={height} className="block">
      <rect
        x={0}
        y={Math.min(bandY1, bandY2)}
        width={width}
        height={Math.abs(bandY2 - bandY1)}
        fill="#10B981"
        opacity={0.08}
      />
      <polyline
        points={pts}
        fill="none"
        stroke={breached ? '#EF4444' : '#00C9A7'}
        strokeWidth={1.5}
        strokeLinejoin="round"
        strokeLinecap="round"
      />
    </svg>
  );
}
