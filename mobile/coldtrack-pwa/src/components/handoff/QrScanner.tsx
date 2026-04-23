import { useEffect, useRef, useState } from 'react';
import { startQrScan, type QrScanHandle } from '@/lib/qrScan';
import { BigButton } from '@/components/ui/BigButton';

interface Props {
  onDecode(text: string): void;
  onCancel(): void;
}

export function QrScanner({ onDecode, onCancel }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const handleRef = useRef<QrScanHandle | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;

    const run = async () => {
      if (!videoRef.current) return;
      try {
        const handle = await startQrScan(
          videoRef.current,
          (text) => {
            if (!mounted) return;
            onDecode(text);
          },
          (err) => setError(err instanceof Error ? err.message : String(err)),
        );
        handleRef.current = handle;
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
      }
    };

    void run();

    return () => {
      mounted = false;
      handleRef.current?.stop();
    };
  }, [onDecode]);

  return (
    <div className="fixed inset-0 z-40 bg-bg-primary flex flex-col">
      <div className="flex-1 relative overflow-hidden">
        <video ref={videoRef} playsInline muted className="w-full h-full object-cover" />
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <div className="w-64 h-64 border-2 border-teal/80 rounded-sm relative">
            <div className="absolute inset-0 border-2 border-teal animate-pulse-amber" />
          </div>
        </div>
        {error && (
          <div className="absolute bottom-24 inset-x-4 p-3 bg-red-tint border border-red text-red text-sm font-mono">
            {error}
          </div>
        )}
      </div>
      <div className="p-4 bg-bg-secondary border-t border-border">
        <BigButton variant="ghost" onClick={onCancel}>
          Cancel scan
        </BigButton>
      </div>
    </div>
  );
}
