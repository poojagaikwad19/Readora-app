import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_endpoints.dart';
import '../services/storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class ApiClient {
  final StorageService _storageService;
  String _baseUrl;

  ApiClient(this._storageService) : _baseUrl = '' {
    final savedUrl = _storageService.getBaseUrl();
    if (savedUrl != null &&
        (savedUrl.contains('127.0.0.1') ||
         savedUrl.contains('192.168.1.50') ||
         savedUrl.contains('192.168.1.59')) &&
        Platform.isAndroid) {
      _baseUrl = ApiEndpoints.defaultBaseUrl;
      _storageService.saveBaseUrl(_baseUrl);
    } else {
      _baseUrl = savedUrl ?? ApiEndpoints.defaultBaseUrl;
    }
  }

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String newUrl) {
    _baseUrl = newUrl.endsWith('/') ? newUrl.substring(0, newUrl.length - 1) : newUrl;
    _storageService.saveBaseUrl(_baseUrl);
    debugPrint('⚙️ [API CONFIG] Updated Base URL to: $_baseUrl');
  }

  Map<String, String> _getHeaders({bool isMultipart = false}) {
    final token = _storageService.getToken();
    final headers = <String, String>{};

    if (!isMultipart) {
      headers['Content-Type'] = 'application/json';
    }

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  void _logRequest(String method, Uri url, {dynamic body}) {
    debugPrint('--------------------------------------------------');
    debugPrint('🌐 [API REQUEST] -> $method $url');
    if (body != null) {
      debugPrint('   📦 Body: $body');
    }
  }

  void _logResponse(String method, Uri url, int statusCode, dynamic jsonBody) {
    debugPrint('✅ [API RESPONSE] <- Status $statusCode | $method $url');
    debugPrint('--------------------------------------------------');
  }

  void _logError(String method, Uri url, dynamic error) {
    debugPrint('❌ [API ERROR] <- $method $url');
    debugPrint('   ⚠️ Details: $error');
    debugPrint('--------------------------------------------------');
  }

  Future<dynamic> _executeWithFallback(Future<dynamic> Function(String currentBaseUrl) requestFn) async {
    final urlsToTry = <String>[
      if (_baseUrl.isNotEmpty) _baseUrl,
      'http://192.168.1.68:5000/api',
      ApiEndpoints.defaultBaseUrl,
      if (Platform.isAndroid) 'http://10.0.2.2:5000/api',
      'http://127.0.0.1:5000/api',
      'http://localhost:5000/api',
    ].where((url) => url.isNotEmpty).toSet().toList();

    dynamic lastException;
    for (int i = 0; i < urlsToTry.length; i++) {
      final candidateUrl = urlsToTry[i];
      try {
        final result = await requestFn(candidateUrl);

        if (_baseUrl != candidateUrl) {
          updateBaseUrl(candidateUrl);
        }
        return result;
      } catch (e) {
        lastException = e;
        if (e is ApiException) rethrow;
      }
    }
    throw _handleError(lastException);
  }

  Future<dynamic> get(String endpoint) async {
    return _executeWithFallback((currentBaseUrl) async {
      final url = Uri.parse('$currentBaseUrl$endpoint');
      _logRequest('GET', url);
      try {
        final response = await http.get(url, headers: _getHeaders()).timeout(
          const Duration(seconds: 30),
        );
        return _processResponse('GET', url, response);
      } catch (e) {
        _logError('GET', url, e);
        rethrow;
      }
    });
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    return _executeWithFallback((currentBaseUrl) async {
      final url = Uri.parse('$currentBaseUrl$endpoint');
      _logRequest('POST', url, body: body);
      try {
        final response = await http
            .post(
              url,
              headers: _getHeaders(),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 120));
        return _processResponse('POST', url, response);
      } catch (e) {
        _logError('POST', url, e);
        rethrow;
      }
    });
  }

  Future<dynamic> uploadFile(
    String endpoint,
    String filePath,
    String fileFieldName, {
    Map<String, String>? fields,
  }) async {
    return _executeWithFallback((currentBaseUrl) async {
      final url = Uri.parse('$currentBaseUrl$endpoint');
      _logRequest('POST (UPLOAD)', url, body: {'file': filePath, ...?fields});
      try {
        final request = http.MultipartRequest('POST', url);
        request.headers.addAll(_getHeaders(isMultipart: true));
        if (fields != null) {
          request.fields.addAll(fields);
        }

        final file = await http.MultipartFile.fromPath(fileFieldName, filePath);
        request.files.add(file);

        final streamedResponse = await request.send().timeout(const Duration(seconds: 300));
        final response = await http.Response.fromStream(streamedResponse);
        return _processResponse('POST (UPLOAD)', url, response);
      } catch (e) {
        _logError('POST (UPLOAD)', url, e);
        rethrow;
      }
    });
  }

  Future<dynamic> delete(String endpoint) async {
    return _executeWithFallback((currentBaseUrl) async {
      final url = Uri.parse('$currentBaseUrl$endpoint');
      _logRequest('DELETE', url);
      try {
        final response = await http.delete(url, headers: _getHeaders()).timeout(
          const Duration(seconds: 15),
        );
        return _processResponse('DELETE', url, response);
      } catch (e) {
        _logError('DELETE', url, e);
        rethrow;
      }
    });
  }

  dynamic _processResponse(String method, Uri url, http.Response response) {
    final responseBody = response.body;
    dynamic jsonBody;

    try {
      jsonBody = responseBody.isNotEmpty ? jsonDecode(responseBody) : {};
    } catch (_) {
      jsonBody = {'message': responseBody};
    }

    _logResponse(method, url, response.statusCode, jsonBody);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonBody;
    } else {
      final message = jsonBody is Map && jsonBody.containsKey('message')
          ? jsonBody['message']
          : 'HTTP Error ${response.statusCode}';
      throw ApiException(message, response.statusCode);
    }
  }

  ApiException _handleError(dynamic error) {
    if (error is ApiException) {
      return error;
    } else if (error is SocketException || error is TimeoutException) {
      return ApiException('Unable to connect to server at $_baseUrl. Check your network or IP.');
    } else {
      return ApiException(error.toString());
    }
  }
}
