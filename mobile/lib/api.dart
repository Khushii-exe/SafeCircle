import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Thin client for the SafeCircle FastAPI backend.
class Api {
  Api(this.base);
  final String base;
  String? token;

  Future<void> ensureAuth() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    if (token != null) return;
    final j = await post('/auth/register', {});
    token = j['token'] as String;
    await prefs.setString('token', token!);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (r.statusCode >= 400) {
      final d = body is Map ? body['detail'] : null;
      throw ApiException(d is String ? d : 'Request failed (${r.statusCode})', r.statusCode);
    }
    return body;
  }

  Future<dynamic> get(String path) async {
    try {
      return _decode(await http.get(Uri.parse('$base$path'), headers: _headers).timeout(const Duration(seconds: 10)));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Cannot reach the server. Check your connection.');
    }
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    try {
      return _decode(await http.post(Uri.parse('$base$path'), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 10)));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Cannot reach the server. Check your connection.');
    }
  }
}
