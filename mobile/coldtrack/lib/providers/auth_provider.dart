import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cognito_service.dart';

/// Singleton [CognitoService] for the lifetime of the app.
final cognitoServiceProvider = Provider<CognitoService>((ref) {
  return CognitoService.fromEnv();
});

/// Triggers an initial credential fetch on app start and surfaces the result.
/// Screens can `ref.watch(cognitoBootstrapProvider)` to drive a loading UI.
final cognitoBootstrapProvider =
    FutureProvider<AwsCredentialsSnapshot>((ref) async {
  final service = ref.read(cognitoServiceProvider);
  return service.getCredentials();
});
