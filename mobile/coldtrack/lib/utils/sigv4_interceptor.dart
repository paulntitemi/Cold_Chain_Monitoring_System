import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:dio/dio.dart';

import '../services/cognito_service.dart';

/// Dio interceptor that signs every outgoing request with AWS Signature V4,
/// using temporary credentials from [CognitoService].
///
/// On 401/403 responses it invalidates the cached credentials and retries the
/// request once; after that it surfaces the error.
class SigV4Interceptor extends Interceptor {
  final CognitoService cognito;
  final String region;
  final String service;

  SigV4Interceptor({
    required this.cognito,
    required this.region,
    this.service = 'execute-api',
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final signed = await _sign(options);
      handler.next(signed);
    } on CognitoNotConfigured catch (e) {
      // Quiet, single-line log — no stack trace, no retry.
      developer.log('Skipping request: ${e.message}',
          name: 'SigV4Interceptor');
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          type: DioExceptionType.cancel,
          message: e.message,
        ),
      );
    } catch (e, st) {
      developer.log('SigV4 signing failed: $e',
          name: 'SigV4Interceptor', error: e, stackTrace: st);
      handler.reject(
        DioException(
          requestOptions: options,
          error: e,
          type: DioExceptionType.unknown,
          message: 'Failed to sign request: $e',
        ),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Never try to refresh credentials when Cognito isn't configured —
    // we'd just spam AWS with invalid pool IDs.
    if (err.error is CognitoNotConfigured) {
      return handler.next(err);
    }

    final status = err.response?.statusCode;
    final alreadyRetried = err.requestOptions.extra['__sigv4_retried'] == true;

    if ((status == 401 || status == 403) && !alreadyRetried) {
      developer.log(
        'Auth error $status — refreshing Cognito credentials and retrying once',
        name: 'SigV4Interceptor',
      );
      cognito.invalidate();

      try {
        await cognito.getCredentials(force: true);
        final retryOptions = err.requestOptions
          ..extra['__sigv4_retried'] = true;

        final signed = await _sign(retryOptions);
        final dio = Dio();
        final response = await dio.fetch(signed);
        return handler.resolve(response);
      } catch (retryErr) {
        developer.log('SigV4 retry failed: $retryErr',
            name: 'SigV4Interceptor');
        return handler.next(err);
      }
    }

    handler.next(err);
  }

  Future<RequestOptions> _sign(RequestOptions options) async {
    final creds = await cognito.getCredentials();

    final uri = options.uri;
    final body = options.data;

    String bodyString;
    if (body == null) {
      bodyString = '';
    } else if (body is String) {
      bodyString = body;
    } else {
      bodyString = jsonEncode(body);
    }

    final request = AWSHttpRequest(
      method: _mapMethod(options.method),
      uri: uri,
      headers: {
        'host': uri.host,
        'content-type':
            options.headers['content-type'] as String? ?? 'application/json',
        if (bodyString.isNotEmpty) 'content-length': '${bodyString.length}',
      },
      body: utf8.encode(bodyString),
    );

    final signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(
        AWSCredentials(
          creds.accessKeyId,
          creds.secretAccessKey,
          creds.sessionToken,
        ),
      ),
    );

    final scope = AWSCredentialScope(region: region, service: AWSService(service));
    final signed = await signer.sign(request, credentialScope: scope);

    // Merge signed headers back onto Dio's RequestOptions
    final mergedHeaders = Map<String, dynamic>.from(options.headers);
    signed.headers.forEach((key, value) => mergedHeaders[key] = value);

    // Make sure data is kept as originally supplied (Dio handles encoding).
    return options.copyWith(headers: mergedHeaders);
  }

  AWSHttpMethod _mapMethod(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return AWSHttpMethod.get;
      case 'POST':
        return AWSHttpMethod.post;
      case 'PUT':
        return AWSHttpMethod.put;
      case 'DELETE':
        return AWSHttpMethod.delete;
      case 'PATCH':
        return AWSHttpMethod.patch;
      case 'HEAD':
        return AWSHttpMethod.head;
      default:
        return AWSHttpMethod.get;
    }
  }
}
