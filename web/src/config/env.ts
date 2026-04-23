interface EnvConfig {
  awsRegion: string;
  cognitoIdentityPoolId: string;
  apiGatewayBaseUrl: string;
  wsEndpoint: string;
  useWebSocket: boolean;
  requireAuth: boolean;
  cognitoUserPoolId: string;
  cognitoUserPoolClientId: string;
  googleMapsApiKey: string;
  enableAudioAlerts: boolean;
  useMockData: boolean;
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
  wsEndpoint: str('VITE_WS_ENDPOINT'),
  useWebSocket: bool('VITE_USE_WEBSOCKET', false),
  requireAuth: bool('VITE_REQUIRE_AUTH', false),
  cognitoUserPoolId: str('VITE_COGNITO_USER_POOL_ID'),
  cognitoUserPoolClientId: str('VITE_COGNITO_USER_POOL_CLIENT_ID'),
  googleMapsApiKey: str('VITE_GOOGLE_MAPS_API_KEY'),
  enableAudioAlerts: bool('VITE_ENABLE_AUDIO_ALERTS', true),
  useMockData: bool('VITE_USE_MOCK_DATA', true),
};
