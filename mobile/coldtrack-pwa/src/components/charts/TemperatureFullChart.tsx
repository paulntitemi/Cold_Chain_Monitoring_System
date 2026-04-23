import { format } from 'date-fns';
import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceArea,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import type { TemperatureReading } from '@/types/shipment';

interface ExcursionSpan {
  start: string;
  end: string;
}

interface AlertMarker {
  timestamp: string;
  label: string;
}

interface Props {
  readings: TemperatureReading[];
  minSafe?: number;
  maxSafe?: number;
  excursions?: ExcursionSpan[];
  alertMarkers?: AlertMarker[];
  height?: number;
}

function computeExcursions(
  readings: TemperatureReading[],
  min: number,
  max: number,
): ExcursionSpan[] {
  const out: ExcursionSpan[] = [];
  let inside = true;
  let startTs: string | null = null;

  for (const r of readings) {
    const breach = r.temperature < min || r.temperature > max;
    if (breach && inside) {
      inside = false;
      startTs = r.timestamp;
    } else if (!breach && !inside && startTs) {
      out.push({ start: startTs, end: r.timestamp });
      inside = true;
      startTs = null;
    }
  }
  if (!inside && startTs) {
    out.push({ start: startTs, end: readings[readings.length - 1].timestamp });
  }
  return out;
}

export function TemperatureFullChart({
  readings,
  minSafe = 2.0,
  maxSafe = 8.0,
  excursions,
  alertMarkers,
  height = 240,
}: Props) {
  const data = readings.map((r) => ({
    ts: new Date(r.timestamp).getTime(),
    temp: r.temperature,
  }));
  const spans = excursions ?? computeExcursions(readings, minSafe, maxSafe);

  return (
    <div style={{ height }} className="w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 10, right: 10, bottom: 0, left: -12 }}>
          <CartesianGrid strokeDasharray="2 4" stroke="#1E2D45" />
          <XAxis
            dataKey="ts"
            type="number"
            domain={['dataMin', 'dataMax']}
            tickFormatter={(v) => format(v as number, 'HH:mm')}
            tick={{ fill: '#64748B', fontSize: 11, fontFamily: 'IBM Plex Mono' }}
            stroke="#1E2D45"
          />
          <YAxis
            tick={{ fill: '#64748B', fontSize: 11, fontFamily: 'IBM Plex Mono' }}
            stroke="#1E2D45"
            domain={[
              (dataMin: number) => Math.min(dataMin - 1, minSafe - 1),
              (dataMax: number) => Math.max(dataMax + 1, maxSafe + 2),
            ]}
            unit="°C"
          />
          <ReferenceArea
            y1={minSafe}
            y2={maxSafe}
            fill="#10B981"
            fillOpacity={0.08}
            stroke="#10B981"
            strokeOpacity={0.2}
          />
          {spans.map((span, i) => (
            <ReferenceArea
              key={`exc-${i}`}
              x1={new Date(span.start).getTime()}
              x2={new Date(span.end).getTime()}
              fill="#EF4444"
              fillOpacity={0.16}
            />
          ))}
          {(alertMarkers ?? []).map((m, i) => (
            <ReferenceLine
              key={`mark-${i}`}
              x={new Date(m.timestamp).getTime()}
              stroke="#F59E0B"
              strokeDasharray="4 4"
              label={{ value: m.label, fill: '#F59E0B', fontSize: 10 }}
            />
          ))}
          <Tooltip
            contentStyle={{
              background: '#0D1420',
              border: '1px solid #2A3F5F',
              borderRadius: 2,
              fontFamily: 'IBM Plex Mono',
              fontSize: 11,
            }}
            labelFormatter={(v) => format(v as number, 'HH:mm:ss')}
            formatter={(v) => [`${v}°C`, 'Temp']}
          />
          <Line
            type="monotone"
            dataKey="temp"
            stroke="#00C9A7"
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 3, fill: '#00C9A7' }}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
