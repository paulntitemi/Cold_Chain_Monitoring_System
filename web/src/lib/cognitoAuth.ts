import { Amplify } from 'aws-amplify';
import { fetchAuthSession } from 'aws-amplify/auth';
import { env } from '@/config/env';
import type { AwsCredentials } from './sigv4';

/**
 * Phase 1: unauthenticated guest access via Cognito Identity Pool — same pool
 * the mobile app uses. We cache temporary credentials in memory and refresh
 * 5 minutes before expiry. No localStorage — credentials never survive reload.
 *
 * Phase 2: swap in a User Pool login when VITE_REQUIRE_AUTH=true; the fetch
 * signature below does not change, only Amplify.configure() gains a
 * userPoolId/client id.
 */

let cached: { creds: AwsCredentials; fetchedAt: number } | null = null;
let inflight: Promise<AwsCredentials> | null = null;

let configured = false;

function configure() {
  if (configured) return;
  if (!env.cognitoIdentityPoolId) return;
  const cognito: Record<string, unknown> = {
    identityPoolId: env.cognitoIdentityPoolId,
    allowGuestAccess: true,
  };
  if (env.requireAuth && env.cognitoUserPoolId && env.cognitoUserPoolClientId) {
    cognito.userPoolId = env.cognitoUserPoolId;
    cognito.userPoolClientId = env.cognitoUserPoolClientId;
  }
  // Amplify's typings require a union of config shapes; we build the object
  // above and cast, since the identity-pool-only mode is a valid runtime shape.
  Amplify.configure({ Auth: { Cognito: cognito } } as never);
  configured = true;
}

function shouldRefresh(creds: AwsCredentials): boolean {
  if (!creds.expiration) return false;
  const msUntilExpiry = creds.expiration.getTime() - Date.now();
  return msUntilExpiry < 5 * 60_000;
}

export async function getAwsCredentials(): Promise<AwsCredentials> {
  if (cached && !shouldRefresh(cached.creds)) return cached.creds;
  if (inflight) return inflight;

  inflight = (async () => {
    configure();
    const session = await fetchAuthSession({ forceRefresh: !!cached });
    const c = session.credentials;
    if (!c?.accessKeyId || !c?.secretAccessKey) {
      throw new Error('No AWS credentials from Cognito session');
    }
    const creds: AwsCredentials = {
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      expiration: c.expiration ? new Date(c.expiration) : undefined,
    };
    cached = { creds, fetchedAt: Date.now() };
    return creds;
  })();

  try {
    return await inflight;
  } finally {
    inflight = null;
  }
}

export function clearCachedCredentials(): void {
  cached = null;
}
