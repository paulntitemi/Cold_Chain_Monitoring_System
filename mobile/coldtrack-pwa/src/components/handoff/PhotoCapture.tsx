import { useRef, useState } from 'react';
import { BigButton } from '@/components/ui/BigButton';

interface Props {
  onCapture(dataUrl: string): void;
  existingPhoto?: string | null;
}

/**
 * Uses <input capture="environment"> — reliable on iOS (where getUserMedia
 * in a PWA can be blocked) and Android. The returned data URL is stored
 * in-memory until upload; the real path will replace the data URL with a
 * presigned S3 URL.
 */
export function PhotoCapture({ onCapture, existingPhoto }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(existingPhoto ?? null);

  const handleChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const url = reader.result as string;
      setPreview(url);
      onCapture(url);
    };
    reader.readAsDataURL(file);
  };

  return (
    <div className="space-y-2">
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        capture="environment"
        className="hidden"
        onChange={handleChange}
      />
      {preview ? (
        <div className="border border-border rounded-sm overflow-hidden">
          <img src={preview} alt="Handoff" className="w-full aspect-video object-cover" />
        </div>
      ) : (
        <div className="border border-dashed border-border rounded-sm aspect-video flex items-center justify-center text-text-secondary text-sm font-mono">
          No photo yet
        </div>
      )}
      <BigButton variant="ghost" height="md" onClick={() => inputRef.current?.click()}>
        {preview ? 'Retake photo' : 'Take photo'}
      </BigButton>
    </div>
  );
}
