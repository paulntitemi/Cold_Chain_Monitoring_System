/**
 * AWS SigV4 request signing for the browser.
 *
 * Signs a fully-formed Request for the API Gateway target using temporary
 * credentials from Cognito (see cognitoAuth.ts). The signed headers are
 * merged into the axios request in apiClient.ts.
 *
 * We implement SigV4 against SubtleCrypto rather than pulling in the
 * @aws-sdk/signature-v4 package — it's ~80 lines of crypto and keeps the
 * bundle lean. Reference: AWS SigV4 signing process docs.
 */

export interface AwsCredentials {
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken?: string;
  expiration?: Date;
}

export interface SigV4Input {
  method: string;
  url: string;
  region: string;
  service: string;
  body?: string;
  headers?: Record<string, string>;
  credentials: AwsCredentials;
}

const enc = new TextEncoder();

async function sha256Hex(data: string | ArrayBuffer): Promise<string> {
  const buf = typeof data === 'string' ? enc.encode(data) : new Uint8Array(data);
  const hash = await crypto.subtle.digest('SHA-256', buf);
  return toHex(hash);
}

async function hmac(key: ArrayBuffer | Uint8Array, data: string): Promise<ArrayBuffer> {
  const keyBuf = key instanceof Uint8Array ? key : new Uint8Array(key);
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    keyBuf,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return crypto.subtle.sign('HMAC', cryptoKey, enc.encode(data));
}

function toHex(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0');
  }
  return hex;
}

function amzDate(d = new Date()): { amz: string; date: string } {
  const iso = d.toISOString().replace(/[:-]|\.\d{3}/g, '');
  return { amz: iso, date: iso.slice(0, 8) };
}

function canonicalQuery(search: string): string {
  const params = new URLSearchParams(search);
  const entries: Array<[string, string]> = [];
  params.forEach((v, k) => entries.push([k, v]));
  entries.sort((a, b) => (a[0] === b[0] ? a[1].localeCompare(b[1]) : a[0].localeCompare(b[0])));
  return entries
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
}

export async function signRequest(input: SigV4Input): Promise<Record<string, string>> {
  const url = new URL(input.url);
  const body = input.body ?? '';
  const { amz, date } = amzDate();
  const host = url.host;
  const payloadHash = await sha256Hex(body);

  const baseHeaders: Record<string, string> = {
    host,
    'x-amz-date': amz,
    'x-amz-content-sha256': payloadHash,
    ...(input.credentials.sessionToken
      ? { 'x-amz-security-token': input.credentials.sessionToken }
      : {}),
    ...(input.headers ?? {}),
  };

  const sortedHeaderKeys = Object.keys(baseHeaders)
    .map((k) => k.toLowerCase())
    .sort();

  const canonicalHeaders =
    sortedHeaderKeys
      .map((k) => `${k}:${(baseHeaders[k] ?? baseHeaders[Object.keys(baseHeaders).find((h) => h.toLowerCase() === k) ?? k] ?? '').trim()}`)
      .join('\n') + '\n';
  const signedHeaders = sortedHeaderKeys.join(';');

  const canonicalRequest = [
    input.method.toUpperCase(),
    url.pathname || '/',
    canonicalQuery(url.search),
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const scope = `${date}/${input.region}/${input.service}/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amz,
    scope,
    await sha256Hex(canonicalRequest),
  ].join('\n');

  const kDate = await hmac(enc.encode(`AWS4${input.credentials.secretAccessKey}`), date);
  const kRegion = await hmac(kDate, input.region);
  const kService = await hmac(kRegion, input.service);
  const kSigning = await hmac(kService, 'aws4_request');
  const sigBuf = await hmac(kSigning, stringToSign);
  const signature = toHex(sigBuf);

  const authorization =
    `AWS4-HMAC-SHA256 Credential=${input.credentials.accessKeyId}/${scope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;

  return {
    ...baseHeaders,
    Authorization: authorization,
  };
}
