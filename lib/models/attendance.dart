/// A student's private attendance history, mirroring `StudentAttendanceSummary`.
class AttendanceSummary {
  final int totalSessions;
  final int attendedSessions;
  final int presentSessions;
  final int lateSessions;
  final int absentSessions;
  final double attendancePercentage;
  final List<AttendanceHistoryEntry> history;

  const AttendanceSummary({
    required this.totalSessions,
    required this.attendedSessions,
    required this.presentSessions,
    required this.lateSessions,
    required this.absentSessions,
    required this.attendancePercentage,
    required this.history,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) => AttendanceSummary(
        totalSessions: json['total_sessions'] as int? ?? 0,
        attendedSessions: json['attended_sessions'] as int? ?? 0,
        presentSessions: json['present_sessions'] as int? ?? 0,
        lateSessions: json['late_sessions'] as int? ?? 0,
        absentSessions: json['absent_sessions'] as int? ?? 0,
        attendancePercentage: (json['attendance_percentage'] as num?)?.toDouble() ?? 0,
        history: ((json['history'] as List?) ?? const [])
            .map((e) => AttendanceHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A teacher-run attendance session, mirroring the API `AttendanceSessionResponse`.
class AttendanceSession {
  final String id;
  final String classId;
  final String? roomName;
  final String? roomCode;
  final String title;
  final String status; // active | completed
  final DateTime startedAt;
  final DateTime? endedAt;

  const AttendanceSession({
    required this.id,
    required this.classId,
    required this.roomName,
    required this.roomCode,
    required this.title,
    required this.status,
    required this.startedAt,
    required this.endedAt,
  });

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';

  factory AttendanceSession.fromJson(Map<String, dynamic> json) => AttendanceSession(
        id: json['id'] as String,
        classId: json['class_id'] as String,
        roomName: json['room_name'] as String?,
        roomCode: json['room_code'] as String?,
        title: json['title'] as String? ?? 'Session',
        status: json['status'] as String? ?? 'completed',
        startedAt:
            DateTime.tryParse(json['started_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        endedAt: DateTime.tryParse(json['ended_at'] as String? ?? '')?.toLocal(),
      );
}

/// An immutable teacher correction to a student's status, mirroring the API
/// `AttendanceOverrideResponse`.
class AttendanceOverride {
  final String id;
  final String status; // present | late | absent
  final String reason;
  final String teacherId;
  final String teacherName;
  final DateTime createdAt;

  const AttendanceOverride({
    required this.id,
    required this.status,
    required this.reason,
    required this.teacherId,
    required this.teacherName,
    required this.createdAt,
  });

  factory AttendanceOverride.fromJson(Map<String, dynamic> json) => AttendanceOverride(
        id: json['id'] as String,
        status: json['status'] as String,
        reason: json['reason'] as String? ?? '',
        teacherId: json['teacher_id'] as String,
        teacherName: json['teacher_name'] as String? ?? 'Teacher',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

/// One student's attendance within a single session, mirroring the API
/// `AttendanceRecordResponse`. `effectiveStatus` already reflects the latest
/// teacher override when one exists.
class AttendanceRecord {
  final String studentId;
  final String studentName;
  final String rollNumber;
  final String automatedStatus;
  final String effectiveStatus;
  final int observedWindows;
  final int eligibleWindows;
  final double presencePercentage;
  final AttendanceOverride? latestOverride;

  const AttendanceRecord({
    required this.studentId,
    required this.studentName,
    required this.rollNumber,
    required this.automatedStatus,
    required this.effectiveStatus,
    required this.observedWindows,
    required this.eligibleWindows,
    required this.presencePercentage,
    required this.latestOverride,
  });

  bool get isOverridden => latestOverride != null;

  String get initials {
    final parts =
        studentName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        studentId: json['student_id'] as String,
        studentName: json['student_name'] as String? ?? 'Student',
        rollNumber: json['roll_number'] as String? ?? '',
        automatedStatus: json['automated_status'] as String? ?? 'absent',
        effectiveStatus: json['effective_status'] as String? ?? 'absent',
        observedWindows: json['observed_windows'] as int? ?? 0,
        eligibleWindows: json['eligible_windows'] as int? ?? 0,
        presencePercentage: (json['presence_percentage'] as num?)?.toDouble() ?? 0,
        latestOverride: json['latest_override'] == null
            ? null
            : AttendanceOverride.fromJson(
                json['latest_override'] as Map<String, dynamic>),
      );

  AttendanceRecord copyWith({
    String? effectiveStatus,
    AttendanceOverride? latestOverride,
  }) =>
      AttendanceRecord(
        studentId: studentId,
        studentName: studentName,
        rollNumber: rollNumber,
        automatedStatus: automatedStatus,
        effectiveStatus: effectiveStatus ?? this.effectiveStatus,
        observedWindows: observedWindows,
        eligibleWindows: eligibleWindows,
        presencePercentage: presencePercentage,
        latestOverride: latestOverride ?? this.latestOverride,
      );
}

class AttendanceHistoryEntry {
  final String sessionId;
  final String classId;
  final String className;
  final String sessionTitle;
  final DateTime sessionStartedAt;
  final String automatedStatus; // present | late | absent
  final String effectiveStatus;
  final int observedWindows;
  final int eligibleWindows;
  final double presencePercentage;

  const AttendanceHistoryEntry({
    required this.sessionId,
    required this.classId,
    required this.className,
    required this.sessionTitle,
    required this.sessionStartedAt,
    required this.automatedStatus,
    required this.effectiveStatus,
    required this.observedWindows,
    required this.eligibleWindows,
    required this.presencePercentage,
  });

  factory AttendanceHistoryEntry.fromJson(Map<String, dynamic> json) => AttendanceHistoryEntry(
        sessionId: json['session_id'] as String,
        classId: json['class_id'] as String,
        className: json['class_name'] as String,
        sessionTitle: json['session_title'] as String,
        sessionStartedAt:
            DateTime.tryParse(json['session_started_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        automatedStatus: json['automated_status'] as String,
        effectiveStatus: json['effective_status'] as String,
        observedWindows: json['observed_windows'] as int? ?? 0,
        eligibleWindows: json['eligible_windows'] as int? ?? 0,
        presencePercentage: (json['presence_percentage'] as num?)?.toDouble() ?? 0,
      );
}
