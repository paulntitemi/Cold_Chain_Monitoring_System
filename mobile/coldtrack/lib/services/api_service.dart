import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../config/env.dart';
import '../models/incident_log.dart';
import '../models/sensor_reading.dart';
import '../models/storage_centre.dart';
import '../utils/constants.dart';
import '../utils/sigv4_interceptor.dart';
import 'cognito_service.dart';
export 'cognito_service.dart' show CognitoNotConfigured;

/// Typed client for the ColdTrack backend (API Gateway → Lambda → DynamoDB).
class ApiService {
  final Dio _dio;
  final String baseUrl;

  ApiService._(this._dio, this.baseUrl);

  factory ApiService.build({required CognitoService cognito}) {
    final baseUrl = Env.apiGatewayBaseUrl;
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(SigV4Interceptor(
      cognito: cognito,
      region: Env.awsRegion,
    ));

    return ApiService._(dio, baseUrl);
  }

  // -------------------------------------------------------------------------
  // Sensor readings
  // -------------------------------------------------------------------------

  /// GET /devices/{deviceId}/readings?limit=N
  Future<List<SensorReading>> getReadings(
    String deviceId, {
    int limit = 20,
  }) async {
    final response = await _dio.get(
      '/devices/$deviceId/readings',
      queryParameters: {'limit': limit},
    );
    return _parseReadingsResponse(response.data, deviceId);
  }

  /// GET /devices/{deviceId}/readings/latest
  Future<SensorReading?> getLatestReading(String deviceId) async {
    final response = await _dio.get('/devices/$deviceId/readings/latest');

    final data = response.data;
    if (data == null) return null;

    if (data is Map<String, dynamic>) {
      final latest = data['latestReading'] ?? data;
      if (latest is Map<String, dynamic>) {
        return SensorReading.fromJson({
          'deviceId': data['deviceId'] ?? deviceId,
          ...latest,
        });
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Incidents
  // -------------------------------------------------------------------------

  /// POST /incidents
  Future<void> logIncident(IncidentLog incident) async {
    try {
      await _dio.post('/incidents', data: incident.toJson());
    } on DioException catch (e) {
      developer.log('Failed to post incident: $e', name: 'ApiService');
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Storage centres
  // -------------------------------------------------------------------------

  /// GET /storage-centres?lat=&lng=&radius=
  ///
  /// Falls back to [AppConstants.fallbackStorageCentres] if the endpoint is
  /// not yet deployed (any non-2xx or network error). This is Phase-1
  /// behaviour and should be removed once the backend endpoint is live.
  /// TODO: remove fallback once GET /storage-centres is deployed.
  Future<List<StorageCentre>> getStorageCentres({
    required double lat,
    required double lng,
    double radiusKm = AppConstants.storageCentreSearchRadiusKm,
  }) async {
    try {
      final response = await _dio.get(
        '/storage-centres',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          'radius': radiusKm,
        },
      );

      final data = response.data;
      if (data is List) {
        return data
            .map((e) => StorageCentre.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (data is Map && data['centres'] is List) {
        return (data['centres'] as List)
            .map((e) => StorageCentre.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      developer.log(
        'Unexpected storage centres payload shape — using fallback',
        name: 'ApiService',
      );
      return AppConstants.fallbackStorageCentres;
    } on DioException catch (e) {
      if (e.error is CognitoNotConfigured) {
        developer.log(
          'Storage centres: using offline fallback (AWS not configured)',
          name: 'ApiService',
        );
      } else {
        developer.log(
          'Storage centres endpoint unavailable (${e.message}) — using fallback',
          name: 'ApiService',
        );
      }
      return AppConstants.fallbackStorageCentres;
    } catch (e) {
      developer.log(
        'Storage centres endpoint unavailable ($e) — using fallback',
        name: 'ApiService',
      );
      return AppConstants.fallbackStorageCentres;
    }
  }

  // -------------------------------------------------------------------------
  // Parsing helpers
  // -------------------------------------------------------------------------

  List<SensorReading> _parseReadingsResponse(dynamic data, String deviceId) {
    if (data is List) {
      return data
          .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is Map<String, dynamic>) {
      final readings = data['readings'];
      final resolvedDeviceId = (data['deviceId'] ?? deviceId) as String;
      if (readings is List) {
        return readings
            .map((e) => SensorReading.fromJson({
                  'deviceId': resolvedDeviceId,
                  ...(e as Map<String, dynamic>),
                }))
            .toList();
      }
    }
    return const [];
  }
}
