import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/classroom.dart';
import 'auth_store.dart';

/// An error surfaced by the API, carrying a human-readable message and HTTP status.
class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

/// Thin client for the Smart Classroom Attendance FastAPI backend.
///
/// The face-scan enrollment photos are uploaded here; the backend derives the
/// face embeddings itself and writes them to the shared PostgreSQL database,
/// so the same records power the web dashboards and the recognition workers.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  /// Default points at the Android emulator's host loopback. Override at build
  /// time with `--dart-define=API_BASE_URL=...` or in-app via server settings.
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  String _baseUrl = _defaultBaseUrl;
  String? _token;

  String get baseUrl => _baseUrl;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  /// Loads the persisted base URL and token. Call once at startup.
  Future<void> init() async {
    final savedUrl = await AuthStore.getBaseUrl();
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      _baseUrl = normalizeBaseUrl(savedUrl);
    }
    _token = await AuthStore.getToken();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = normalizeBaseUrl(url);
    await AuthStore.setBaseUrl(_baseUrl);
  }

  /// Trims trailing slashes and appends the `/api/v1` prefix when missing.
  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.contains('/api/')) {
      url = '$url/api/v1';
    }
    return url;
  }

  Future<void> _setToken(String? token) async {
    _token = token;
    if (token == null) {
      await AuthStore.clearToken();
    } else {
      await AuthStore.setToken(token);
    }
  }

  Future<void> signOut() => _setToken(null);

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Never _fail(http.Response response) {
    var message = 'Something went wrong. Please try again.';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] != null) {
        final detail = body['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail is List) {
          message = detail
              .map((item) => item is Map && item['msg'] != null ? '${item['msg']}' : '$item')
              .join(' ');
        }
      }
    } catch (_) {
      // Keep the stable fallback for non-JSON error bodies.
    }
    throw ApiException(message, response.statusCode);
  }

  Future<dynamic> _get(String path) async {
    late final http.Response response;
    try {
      response = await http.get(_uri(path), headers: _headers(json: false));
    } on SocketException {
      throw ApiException('Cannot reach the server at $_baseUrl.', 0);
    } on HttpException {
      throw ApiException('Cannot reach the server at $_baseUrl.', 0);
    }
    if (response.statusCode >= 400) _fail(response);
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  Future<dynamic> _post(String path, Object? body) async {
    late final http.Response response;
    try {
      response = await http.post(
        _uri(path),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      );
    } on SocketException {
      throw ApiException('Cannot reach the server at $_baseUrl.', 0);
    } on HttpException {
      throw ApiException('Cannot reach the server at $_baseUrl.', 0);
    }
    if (response.statusCode >= 400) _fail(response);
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  // ---- Auth ---------------------------------------------------------------

  Future<AuthSession> login(String identifier, String password) async {
    final data = await _post('/auth/login', {
      'identifier': identifier.trim(),
      'password': password,
    });
    final session = AuthSession.fromJson(data as Map<String, dynamic>);
    await _setToken(session.accessToken);
    return session;
  }

  Future<AuthSession> registerTeacher({
    required String fullName,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    final data = await _post('/auth/register/teacher', {
      'full_name': fullName.trim(),
      'email': email.trim(),
      'password': password,
      'invite_code': inviteCode.trim(),
    });
    final session = AuthSession.fromJson(data as Map<String, dynamic>);
    await _setToken(session.accessToken);
    return session;
  }

  /// Registers a student by uploading their profile plus exactly three face
  /// photos as multipart form data. The backend validates that each photo has
  /// exactly one detectable face and stores the derived embeddings.
  Future<AuthSession> registerStudent({
    required String fullName,
    required String rollNumber,
    required String email,
    required String password,
    required List<File> photos,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/auth/register/student'))
      ..fields['full_name'] = fullName.trim()
      ..fields['roll_number'] = rollNumber.trim()
      ..fields['email'] = email.trim()
      ..fields['password'] = password;

    for (var i = 0; i < photos.length; i++) {
      request.files.add(await http.MultipartFile.fromPath(
        'photos',
        photos[i].path,
        filename: 'capture-${i + 1}.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    }

    late final http.Response response;
    try {
      response = await http.Response.fromStream(await request.send());
    } on SocketException {
      throw ApiException('Cannot reach the server at $_baseUrl.', 0);
    } on HttpException {
      throw ApiException('Cannot reach the server at $_baseUrl.', 0);
    }
    if (response.statusCode >= 400) _fail(response);
    final session = AuthSession.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    await _setToken(session.accessToken);
    return session;
  }

  Future<AppUser> me() async => AppUser.fromJson(await _get('/auth/me') as Map<String, dynamic>);

  // ---- Classes ------------------------------------------------------------

  Future<List<Classroom>> listClasses() async {
    final data = await _get('/classes') as List;
    return data.map((e) => Classroom.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Classroom> createClass(String name, String section) async {
    final data = await _post('/classes', {
      'name': name.trim(),
      'section': section.trim().isEmpty ? null : section.trim(),
    });
    return Classroom.fromJson(data as Map<String, dynamic>);
  }

  Future<Classroom> joinClass(String joinCode) async {
    final data = await _post('/classes/join', {'join_code': joinCode.trim().toUpperCase()});
    return Classroom.fromJson(data as Map<String, dynamic>);
  }

  // ---- Student attendance -------------------------------------------------

  Future<AttendanceSummary> studentAttendance() async =>
      AttendanceSummary.fromJson(await _get('/student/attendance') as Map<String, dynamic>);
}
