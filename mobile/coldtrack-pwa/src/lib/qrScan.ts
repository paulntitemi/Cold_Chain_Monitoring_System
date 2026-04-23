/**
 * QR scan abstraction: prefers the native Barcode Detection API (Android
 * Chrome, Edge); falls back to @zxing/browser for everything else (iOS
 * Safari in particular).
 */

import { BrowserMultiFormatReader } from '@zxing/browser';

declare global {
  interface Window {
    BarcodeDetector?: new (opts?: { formats: string[] }) => {
      detect(source: HTMLVideoElement | ImageBitmap): Promise<Array<{ rawValue: string }>>;
    };
  }
}

export interface QrScanHandle {
  stop(): void;
}

export function nativeBarcodeSupported(): boolean {
  return typeof window !== 'undefined' && 'BarcodeDetector' in window;
}

export async function startQrScan(
  video: HTMLVideoElement,
  onDecode: (text: string) => void,
  onError?: (err: unknown) => void,
): Promise<QrScanHandle> {
  let stopped = false;

  if (nativeBarcodeSupported()) {
    const BD = window.BarcodeDetector!;
    const detector = new BD({ formats: ['qr_code'] });

    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: 'environment' } },
    });
    video.srcObject = stream;
    await video.play();

    const tick = async () => {
      if (stopped) return;
      try {
        const results = await detector.detect(video);
        if (results.length > 0 && results[0].rawValue) {
          onDecode(results[0].rawValue);
        }
      } catch (err) {
        onError?.(err);
      }
      if (!stopped) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);

    return {
      stop() {
        stopped = true;
        stream.getTracks().forEach((t) => t.stop());
        video.srcObject = null;
      },
    };
  }

  // Fallback: zxing/browser
  const reader = new BrowserMultiFormatReader();
  const controls = await reader.decodeFromVideoDevice(
    undefined,
    video,
    (result, err) => {
      if (result) onDecode(result.getText());
      if (err && err.name !== 'NotFoundException') onError?.(err);
    },
  );

  return {
    stop() {
      stopped = true;
      try {
        controls.stop();
      } catch {
        // ignore
      }
    },
  };
}
