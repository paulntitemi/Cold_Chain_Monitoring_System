/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_AWS_REGION: string;
  readonly VITE_COGNITO_IDENTITY_POOL_ID: string;
  readonly VITE_API_GATEWAY_BASE_URL: string;
  readonly VITE_WS_ENDPOINT: string;
  readonly VITE_USE_WEBSOCKET: string;
  readonly VITE_REQUIRE_AUTH: string;
  readonly VITE_COGNITO_USER_POOL_ID: string;
  readonly VITE_COGNITO_USER_POOL_CLIENT_ID: string;
  readonly VITE_GOOGLE_MAPS_API_KEY: string;
  readonly VITE_ENABLE_AUDIO_ALERTS: string;
  readonly VITE_USE_MOCK_DATA: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
