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
