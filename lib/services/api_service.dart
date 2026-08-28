import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/camera_source.dart';
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
    defaultValue: 'http://192.168.1.8:8000/api/v1',
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

  /// Like [_get] but returns the raw response body instead of decoding JSON,
  /// for endpoints that reply with an image (camera preview frames). Error
  /// bodies are still JSON, so error details are parsed the same way as
  /// [_fail] — e.g. the real reason a webcam couldn't be opened, not a
  /// generic fallback string.
  Future<Uint8List> _getBytes(String path) async {
    late final http.Response response;
    try {
      response = await http.get(_uri(path), headers: _headers(json: false));
    } on SocketException {
      throw ApiException('Cannot reach the server at $_baseUrl.', 0);
    } on HttpException {
      throw ApiException('Cannot reach the server at $_baseUrl.', 0);
    }
    if (response.statusCode >= 400) _fail(response);
    return response.bodyBytes;
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

  /// Issues a DELETE. The backend replies `204 No Content`, so there is no body
  /// to decode; a non-2xx status is surfaced through [_fail].
  Future<void> _delete(String path) async {    late final http.Response response;
  try {
    response = await http.delete(_uri(path), headers: _headers(json: false));
  } on SocketException {
    throw ApiException('Cannot reach the server at $_baseUrl.', 0);
  } on HttpException {
    throw ApiException('Cannot reach the server at $_baseUrl.', 0);
  }
  if (response.statusCode >= 400) _fail(response);
  }

  Future<dynamic> _patch(String path, Object? body) async {
    late final http.Response response;
    try {
      response = await http.patch(
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

  /// Registers a student by uploading their profile plus exactly five face
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

  /// Permanently deletes a teacher-owned class. The backend rejects this with a
  /// `409` while the class still has a live attendance session.
  Future<void> deleteClass(String classId) => _delete('/classes/$classId');

  /// Reports the one class currently running a live session for this teacher,
  /// if any. Every field is null when nothing is live.
  Future<ActiveTeacherSession> activeTeacherSession() async =>
      ActiveTeacherSession.fromJson(await _get('/classes/active-session') as Map<String, dynamic>);

  /// Lists every student enrolled in a class the teacher owns.
  Future<List<ClassStudent>> listClassStudents(String classId) async {
    final data = await _get('/classes/$classId/students') as List;
    return data.map((e) => ClassStudent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// One enrolled student's completed-session attendance history for a single
  /// class the teacher owns.
  Future<AttendanceSummary> studentAttendanceInClass(String classId, String studentId) async =>
      AttendanceSummary.fromJson(
        await _get('/classes/$classId/students/$studentId/attendance') as Map<String, dynamic>,
      );

  // ---- Attendance sessions (teacher) --------------------------------------

  /// Every attendance session (active + completed) for a class the teacher owns,
  /// newest first.
  Future<List<AttendanceSession>> listClassSessions(String classId) async {
    final data = await _get('/classes/$classId/sessions') as List;
    return data.map((e) => AttendanceSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Enabled cameras for the room identified by a room number/code, used to
  /// populate the live-feed source picker before and during a session.
  Future<List<CameraSource>> listTeacherRoomCameras(String roomCode) async {
    final data = await _get('/teacher/rooms/${Uri.encodeComponent(roomCode.trim())}/cameras') as List;
    return data.map((e) => CameraSource.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Starts a live recognition session for a class in the given room. The
  /// backend rejects this with `409` if the class or room already has an
  /// active session, or `422` if the room has no enabled cameras.
  Future<AttendanceSession> startSession({
    required String classId,
    required String title,
    required String roomCode,
    required num qualificationWindowMinutes,
    required int gracePeriodMinutes,
  }) async {
    final data = await _post('/classes/$classId/sessions', {
      'title': title.trim(),
      'room_code': roomCode.trim(),
      'qualification_window_minutes': qualificationWindowMinutes,
      'grace_period_minutes': gracePeriodMinutes,
      'minimum_sightings': 1,
    });
    return AttendanceSession.fromJson(data as Map<String, dynamic>);
  }

  /// Stops a live session and triggers attendance calculation. Returns the
  /// now-completed session.
  Future<AttendanceSession> stopSession(String sessionId) async {
    final data = await _post('/sessions/$sessionId/stop', null);
    return AttendanceSession.fromJson(data as Map<String, dynamic>);
  }

  /// The most recent annotated JPEG frame captured by a camera during a live
  /// session. Throws a 404-flagged [ApiException] while no frame has been
  /// captured yet, which callers should treat as "still waiting" rather than
  /// a hard failure.
  Future<Uint8List> previewCameraFrame(String sessionId, String cameraId) =>
      _getBytes('/sessions/$sessionId/cameras/$cameraId/preview');

  /// Recent face-recognition detections for a live (or completed) session,
  /// newest first.
  Future<List<Sighting>> listSessionSightings(String sessionId) async {
    final data = await _get('/sessions/$sessionId/sightings') as List;
    return data.map((e) => Sighting.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Per-student attendance for one session, including any teacher overrides.
  Future<List<AttendanceRecord>> listSessionAttendance(String sessionId) async {
    final data = await _get('/sessions/$sessionId/attendance') as List;
    return data.map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Records a teacher correction marking a student present / late / absent for a
  /// completed session. The backend rejects this with `409` while the session is
  /// still active.
  Future<AttendanceOverride> overrideAttendance({
    required String sessionId,
    required String studentId,
    required String status,
    String reason = 'Teacher correction',
  }) async {
    final data = await _patch('/sessions/$sessionId/attendance/$studentId', {
      'status': status,
      'reason': reason.trim().isEmpty ? 'Teacher correction' : reason.trim(),
    });
    return AttendanceOverride.fromJson(data as Map<String, dynamic>);
  }

  // ---- Student attendance -------------------------------------------------

  Future<AttendanceSummary> studentAttendance() async =>
      AttendanceSummary.fromJson(await _get('/student/attendance') as Map<String, dynamic>);
}