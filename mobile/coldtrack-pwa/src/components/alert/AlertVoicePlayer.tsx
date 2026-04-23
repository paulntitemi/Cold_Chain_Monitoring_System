import { useEffect } from 'react';
import { env } from '@/config/env';
import { bumpVolume, cancelSpeech, resetVolume, speak } from '@/lib/speech';
import { vibrate, PATTERNS } from '@/lib/haptic';

interface Props {
  script: string;
  escalated?: boolean;
}

/**
 * Speaks the alert sentence every 20s, bumping volume each iteration, and
 * pulses the phone on each repetition. Unmount stops everything.
 */
export function AlertVoicePlayer({ script, escalated }: Props) {
  useEffect(() => {
    if (!env.enableVoiceAlerts) return;
    resetVolume(0.8);

    const fire = () => {
      speak(script, { rate: 1.02, pitch: 1.05 });
      vibrate(escalated ? PATTERNS.alertLoud : PATTERNS.alert);
    };

    fire();
    const id = window.setInterval(() => {
      bumpVolume(0.1);
      fire();
    }, 20_000);

    return () => {
      window.clearInterval(id);
      cancelSpeech();
    };
  }, [script, escalated]);

  return null;
}
