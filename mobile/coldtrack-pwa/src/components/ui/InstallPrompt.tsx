import { useEffect, useState } from 'react';
import { BigButton } from './BigButton';

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

/**
 * Catches `beforeinstallprompt` and surfaces a banner nudging the rider to
 * install. Tap → system prompt. iOS doesn't fire this event — see README
 * for the manual "Add to Home Screen" guidance shown as a fallback.
 */
export function InstallPrompt() {
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null);
  const [installed, setInstalled] = useState(false);

  useEffect(() => {
    const onPrompt = (e: Event) => {
      e.preventDefault();
      setDeferred(e as BeforeInstallPromptEvent);
    };
    const onInstalled = () => {
      setDeferred(null);
      setInstalled(true);
    };
    window.addEventListener('beforeinstallprompt', onPrompt as EventListener);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onPrompt as EventListener);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  if (installed || !deferred) return null;

  return (
    <div className="border border-teal/40 bg-teal/10 rounded-sm p-4 flex flex-col gap-3">
      <div>
        <div className="text-teal font-display font-semibold uppercase tracking-wider text-sm">
          Install ColdTrack
        </div>
        <p className="text-text-primary text-sm mt-1">
          Add to your home screen for one-tap access during trips and for
          offline support.
        </p>
      </div>
      <BigButton
        variant="teal"
        height="md"
        onClick={async () => {
          if (!deferred) return;
          await deferred.prompt();
          const choice = await deferred.userChoice;
          if (choice.outcome === 'accepted') setDeferred(null);
        }}
      >
        Install app
      </BigButton>
    </div>
  );
}
