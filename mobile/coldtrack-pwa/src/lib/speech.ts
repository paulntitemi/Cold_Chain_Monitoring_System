/**
 * Web Speech API wrapper for the Alert voice. Feature-detects; degrades
 * to a silent noop if speechSynthesis is missing (some embedded webviews).
 *
 * Browsers block speechSynthesis.speak() until a user gesture has occurred
 * in the tab. `primeVoice()` is called on the login tap so later calls work.
 */

let primed = false;
let volume = 1;

export function speechSupported(): boolean {
  return typeof window !== 'undefined' && 'speechSynthesis' in window;
}

export function primeVoice(): void {
  if (!speechSupported() || primed) return;
  try {
    const u = new SpeechSynthesisUtterance(' ');
    u.volume = 0;
    window.speechSynthesis.speak(u);
    primed = true;
  } catch {
    // ignore
  }
}

export function speak(text: string, opts?: { rate?: number; pitch?: number; volume?: number }): void {
  if (!speechSupported()) return;
  try {
    window.speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.rate = opts?.rate ?? 1;
    u.pitch = opts?.pitch ?? 1;
    u.volume = opts?.volume ?? volume;
    u.lang = 'en-GB';
    window.speechSynthesis.speak(u);
  } catch {
    // ignore
  }
}

export function cancelSpeech(): void {
  if (!speechSupported()) return;
  try {
    window.speechSynthesis.cancel();
  } catch {
    // ignore
  }
}

export function bumpVolume(delta = 0.1): number {
  volume = Math.min(1, Math.max(0, volume + delta));
  return volume;
}

export function resetVolume(to = 1): void {
  volume = to;
}
