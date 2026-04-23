import 'dart:developer' as developer;

import 'package:amazon_cognito_identity_dart_2/cognito.dart';

import '../config/env.dart';
import '../utils/constants.dart';

/// Snapshot of temporary AWS credentials fetched from Cognito Identity Pool.
/// These are in-memory only — never persisted to disk.
class AwsCredentialsSnapshot {
  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
  final DateTime expiryUtc;

  AwsCredentialsSnapshot({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expiryUtc,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiryUtc);

  bool get needsRefresh => DateTime.now()
      .toUtc()
      .isAfter(expiryUtc.subtract(AppConstants.credentialRefreshLeeway));
}

/// Thrown when Cognito is not configured (e.g. `.env` still has the
/// placeholder pool ID). Callers can surface a friendly "Configure AWS" UI
/// state instead of crash-looping on every signed request.
class CognitoNotConfigured implements Exception {
  final String message;
  const CognitoNotConfigured(this.message);
  @override
  String toString() => 'CognitoNotConfigured: $message';
}

/// Fetches and refreshes guest (unauthenticated) credentials from a Cognito
/// Identity Pool. Phase 2 will add authenticated user-pool login.
class CognitoService {
  // Real Cognito pool IDs look like:  eu-west-1:a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  // The placeholder in `.env.example` is all-x, which we explicitly reject.
  static final RegExp _validPoolIdPattern =
      RegExp(r'^[\w-]+:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  final String identityPoolId;
  final String region;

  CognitoCredentials? _cognitoCreds;
  AwsCredentialsSnapshot? _cached;
  Future<AwsCredentialsSnapshot>? _inflight;

  CognitoService({required this.identityPoolId, required this.region});

  factory CognitoService.fromEnv() => CognitoService(
        identityPoolId: Env.cognitoIdentityPoolId,
        region: Env.awsRegion,
      );

  /// True only when `.env` contains a real Cognito pool ID (not the
  /// `xxxxxxxx-...` placeholder from `.env.example`).
  bool get isConfigured => _validPoolIdPattern.hasMatch(identityPoolId);

  /// Returns a valid, non-expired credential snapshot. Refreshes transparently
  /// when the cached snapshot is near expiry. Throws [CognitoNotConfigured]
  /// immediately when the pool ID is missing or still the placeholder, so
  /// callers do not hammer AWS with malformed requests.
  Future<AwsCredentialsSnapshot> getCredentials({bool force = false}) async {
    if (!isConfigured) {
      throw const CognitoNotConfigured(
        'COGNITO_IDENTITY_POOL_ID is not set (still the .env.example placeholder). '
        'Create an Identity Pool in the AWS Console and paste its ID into .env.',
      );
    }
    if (!force && _cached != null && !_cached!.needsRefresh) {
      return _cached!;
    }
    _inflight ??= _fetch().whenComplete(() => _inflight = null);
    return _inflight!;
  }

  bool get isExpired => _cached?.isExpired ?? true;

  /// Clears the cached snapshot; next call to [getCredentials] will re-fetch.
  void invalidate() {
    _cached = null;
    _cognitoCreds = null;
  }

  Future<AwsCredentialsSnapshot> _fetch() async {
    try {
      _cognitoCreds ??= CognitoCredentials(identityPoolId, _dummyUserPool());
      await _cognitoCreds!.getAwsCredentials(null);

      final Object? rawExpiry = _cognitoCreds!.expireTime;
      DateTime expiry;
      if (rawExpiry is DateTime) {
        expiry = rawExpiry;
      } else if (rawExpiry is int) {
        expiry = DateTime.fromMillisecondsSinceEpoch(rawExpiry, isUtc: true);
      } else {
        expiry = DateTime.now().toUtc().add(const Duration(hours: 1));
      }

      final snapshot = AwsCredentialsSnapshot(
        accessKeyId: _cognitoCreds!.accessKeyId ?? '',
        secretAccessKey: _cognitoCreds!.secretAccessKey ?? '',
        sessionToken: _cognitoCreds!.sessionToken ?? '',
        expiryUtc: expiry.toUtc(),
      );

      if (snapshot.accessKeyId.isEmpty || snapshot.secretAccessKey.isEmpty) {
        throw StateError('Cognito returned empty credentials');
      }

      _cached = snapshot;
      developer.log(
        'Cognito credentials refreshed (expires ${snapshot.expiryUtc.toIso8601String()})',
        name: 'CognitoService',
      );
      return snapshot;
    } catch (e, st) {
      developer.log(
        'Cognito credential fetch failed: $e',
        name: 'CognitoService',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// The guest credential flow does not actually hit the User Pool, but
  /// `CognitoCredentials` requires a `CognitoUserPool` handle. We pass a
  /// placeholder with a well-formed ID to satisfy the constructor.
  CognitoUserPool _dummyUserPool() {
    return CognitoUserPool(
      '${region}_unused000',
      'unauthenticatedclient',
    );
  }
}
