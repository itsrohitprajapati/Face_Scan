// Unit tests for the attendance data models. These avoid plugins/network so
// they run fast and deterministically.

import 'package:flutter_test/flutter_test.dart';

import 'package:face_scan_android/models/app_user.dart';
import 'package:face_scan_android/models/attendance.dart';
import 'package:face_scan_android/models/classroom.dart';
import 'package:face_scan_android/services/api_service.dart';

void main() {
  group('AppUser', () {
    test('parses a student payload and derives display helpers', () {
      final user = AppUser.fromJson(const {
        'id': 'u1',
        'email': 'ada@example.com',
        'full_name': 'Ada Lovelace',
        'role': 'student',
        'roll_number': '21CS042',
        'enrollment_complete': true,
      });

      expect(user.isStudent, isTrue);
      expect(user.isTeacher, isFalse);
      expect(user.rollNumber, '21CS042');
      expect(user.enrollmentComplete, isTrue);
      expect(user.firstName, 'Ada');
      expect(user.initials, 'AL');
    });

    test('initials fall back gracefully for single-word names', () {
      final user = AppUser.fromJson(const {
        'id': 'u2',
        'email': 'teacher@example.com',
        'full_name': 'Turing',
        'role': 'teacher',
      });
      expect(user.isTeacher, isTrue);
      expect(user.initials, 'T');
      expect(user.enrollmentComplete, isFalse);
      expect(user.rollNumber, isNull);
    });
  });

  group('AuthSession', () {
    test('parses token + nested user', () {
      final session = AuthSession.fromJson(const {
        'access_token': 'abc.def.ghi',
        'token_type': 'bearer',
        'user': {
          'id': 'u1',
          'email': 'ada@example.com',
          'full_name': 'Ada Lovelace',
          'role': 'student',
        },
      });
      expect(session.accessToken, 'abc.def.ghi');
      expect(session.user.fullName, 'Ada Lovelace');
    });
  });

  group('Classroom', () {
    test('parses an optional section', () {
      final classroom = Classroom.fromJson(const {
        'id': 'c1',
        'name': 'Data Structures',
        'section': null,
        'join_code': 'AB12CD34',
        'teacher_name': 'Grace Hopper',
      });
      expect(classroom.name, 'Data Structures');
      expect(classroom.section, isNull);
      expect(classroom.joinCode, 'AB12CD34');
    });
  });

  group('AttendanceSummary', () {
    test('parses history entries and defaults missing counters to zero', () {
      final summary = AttendanceSummary.fromJson(const {
        'total_sessions': 2,
        'attended_sessions': 1,
        'present_sessions': 1,
        'attendance_percentage': 50.0,
        'history': [
          {
            'session_id': 's1',
            'class_id': 'c1',
            'class_name': 'Data Structures',
            'session_title': 'Week 1',
            'session_started_at': '2024-08-01T09:00:00Z',
            'automated_status': 'present',
            'effective_status': 'present',
            'observed_windows': 50,
            'eligible_windows': 60,
            'presence_percentage': 83.3,
          }
        ],
      });

      expect(summary.totalSessions, 2);
      expect(summary.lateSessions, 0); // missing key defaults to 0
      expect(summary.absentSessions, 0);
      expect(summary.history, hasLength(1));
      expect(summary.history.single.className, 'Data Structures');
      expect(summary.history.single.observedWindows, 50);
    });
  });

  group('ApiService.normalizeBaseUrl', () {
    test('appends /api/v1 and trims trailing slashes', () {
      expect(ApiService.normalizeBaseUrl('http://10.0.2.2:8000/'),
          'http://10.0.2.2:8000/api/v1');
      expect(ApiService.normalizeBaseUrl('http://host:8000/api/v1'),
          'http://host:8000/api/v1');
    });
  });
}
