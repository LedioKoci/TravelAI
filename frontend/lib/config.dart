// Set via --dart-define=API_BASE_URL=https://your-backend.vercel.app when building.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://backend-puce-chi-41.vercel.app',
);
