import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { env } from '@/config/env';
import { api } from '@/lib/apiClient';
import { primeVoice } from '@/lib/speech';
import { useAuthStore } from '@/store/authStore';
import { BigButton } from '@/components/ui/BigButton';
import { InstallPrompt } from '@/components/ui/InstallPrompt';

export function LoginScreen() {
  const setRider = useAuthStore((s) => s.setRider);
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const handleGuest = async () => {
    setBusy(true);
    setErr(null);
    primeVoice(); // user gesture — unlocks speechSynthesis for the alert voice
    try {
      const rider = await api.getMe();
      setRider(rider);
      navigate('/assignments', { replace: true });
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Login failed');
    } finally {
      setBusy(false);
    }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    // TODO: call real Cognito signIn here when requireAuth is on
    await handleGuest();
  };

  return (
    <div
      className="min-h-screen flex flex-col px-6 py-8 gap-8"
      style={{
        paddingTop: 'calc(env(safe-area-inset-top) + 2rem)',
        paddingBottom: 'calc(env(safe-area-inset-bottom) + 2rem)',
      }}
    >
      <header className="pt-12">
        <div className="font-display font-bold text-5xl text-teal tracking-tight">ColdTrack</div>
        <div className="font-mono text-text-secondary tracking-[0.2em] text-xs uppercase mt-2">
          Rider · v0.1
        </div>
      </header>

      <div className="flex-1 flex flex-col justify-center gap-6">
        {env.requireAuth ? (
          <form className="flex flex-col gap-3" onSubmit={handleLogin}>
            <label className="flex flex-col gap-1">
              <span className="text-xs font-mono uppercase text-text-secondary tracking-wider">Email</span>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="h-12 px-3 bg-bg-secondary border border-border text-text-primary font-body text-lg rounded-sm focus:outline-none focus:border-teal"
              />
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-xs font-mono uppercase text-text-secondary tracking-wider">Password</span>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="h-12 px-3 bg-bg-secondary border border-border text-text-primary font-body text-lg rounded-sm focus:outline-none focus:border-teal"
              />
            </label>
            {err && <div className="text-red text-sm font-mono">{err}</div>}
            <BigButton type="submit" disabled={busy}>
              {busy ? 'Signing in…' : 'Sign in'}
            </BigButton>
          </form>
        ) : (
          <div className="flex flex-col gap-3">
            <p className="text-text-secondary text-sm">
              Phase 1 dev mode — guest sign-in via Cognito Identity Pool. Set{' '}
              <span className="font-mono text-text-primary">VITE_REQUIRE_AUTH=true</span> to enable
              email/password login.
            </p>
            {err && <div className="text-red text-sm font-mono">{err}</div>}
            <BigButton onClick={handleGuest} disabled={busy}>
              {busy ? 'Loading…' : 'Continue as Jake Fletcher'}
            </BigButton>
          </div>
        )}

        <InstallPrompt />
      </div>

      <footer className="text-text-dim text-[10px] font-mono text-center uppercase tracking-[0.2em]">
        ColdTrack · NHS pilot · UK
      </footer>
    </div>
  );
}
