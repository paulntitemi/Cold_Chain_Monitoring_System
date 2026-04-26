interface EnvConfig {
  awsRegion: string;
  cognitoIdentityPoolId: string;
  apiGatewayBaseUrl: string;
  requireAuth: boolean;
  cognitoUserPoolId: string;
  cognitoUserPoolClientId: string;
  googleMapsApiKey: string;
  webPushPublicKey: string;
  useMockData: boolean;
  enableVoiceAlerts: boolean;
  enableWebPush: boolean;
  /**
   * Hybrid demo. When set, this shipment id is overlaid with live data
   * from `liveApiUrl` (the dashboard API). The rest of the app stays on
   * mock data so login, assignments, profile etc. still work end-to-end.
   */
  liveShipmentId: string;
  liveApiUrl: string;
}

function str(key: string, fallback = ''): string {
  const raw = import.meta.env[key];
  return typeof raw === 'string' && raw.length > 0 ? raw : fallback;
}

function bool(key: string, fallback: boolean): boolean {
  const raw = import.meta.env[key];
  if (typeof raw !== 'string') return fallback;
  return raw.toLowerCase() === 'true';
}

export const env: EnvConfig = {
  awsRegion: str('VITE_AWS_REGION', 'eu-west-2'),
  cognitoIdentityPoolId: str('VITE_COGNITO_IDENTITY_POOL_ID'),
  apiGatewayBaseUrl: str('VITE_API_GATEWAY_BASE_URL'),
  requireAuth: bool('VITE_REQUIRE_AUTH', false),
  cognitoUserPoolId: str('VITE_COGNITO_USER_POOL_ID'),
  cognitoUserPoolClientId: str('VITE_COGNITO_USER_POOL_CLIENT_ID'),
  googleMapsApiKey: str('VITE_GOOGLE_MAPS_API_KEY'),
  webPushPublicKey: str('VITE_WEB_PUSH_PUBLIC_KEY'),
  useMockData: bool('VITE_USE_MOCK_DATA', true),
  enableVoiceAlerts: bool('VITE_ENABLE_VOICE_ALERTS', true),
  enableWebPush: bool('VITE_ENABLE_WEB_PUSH', true),
  liveShipmentId: str('VITE_LIVE_SHIPMENT_ID'),
  liveApiUrl: str('VITE_LIVE_API_URL'),
};
