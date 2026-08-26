/// A class/course, mirroring the API `ClassroomResponse`.
class Classroom {
  final String id;
  final String name;
  final String? section;
  final String joinCode;
  final String teacherName;

  const Classroom({
    required this.id,
    required this.name,
    required this.section,
    required this.joinCode,
    required this.teacherName,
  });

  factory Classroom.fromJson(Map<String, dynamic> json) => Classroom(
        id: json['id'] as String,
        name: json['name'] as String,
        section: json['section'] as String?,
        joinCode: json['join_code'] as String,
        teacherName: json['teacher_name'] as String,
      );
}

/// A student enrolled in a class, mirroring the API `ClassStudentResponse`.
class ClassStudent {
  final String id;
  final String fullName;
  final String email;
  final String rollNumber;
  final DateTime joinedAt;

  const ClassStudent({
    required this.id,
    required this.fullName,
    required this.email,
    required this.rollNumber,
    required this.joinedAt,
  });

  factory ClassStudent.fromJson(Map<String, dynamic> json) => ClassStudent(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        rollNumber: json['roll_number'] as String,
        joinedAt: DateTime.tryParse(json['joined_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

/// The teacher's currently running live session, mirroring the API
/// `ActiveTeacherSessionResponse`. Any field may be null when nothing is live.
class ActiveTeacherSession {
  final String? classId;
  final String? className;
  final String? sessionId;

  const ActiveTeacherSession({this.classId, this.className, this.sessionId});

  bool get isActive => sessionId != null;

  factory ActiveTeacherSession.fromJson(Map<String, dynamic> json) => ActiveTeacherSession(
        classId: json['class_id'] as String?,
        className: json['class_name'] as String?,
        sessionId: json['session_id'] as String?,
      );
}
