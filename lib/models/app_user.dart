/// A user of the attendance system, mirroring the API `UserResponse`.
class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String role; // 'admin' | 'teacher' | 'student'
  final String? rollNumber;
  final bool enrollmentComplete;

  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.rollNumber,
    this.enrollmentComplete = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
        rollNumber: json['roll_number'] as String?,
        enrollmentComplete: json['enrollment_complete'] as bool? ?? false,
      );

  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';
  bool get isAdmin => role == 'admin';

  String get firstName =>
      fullName.trim().isEmpty ? fullName : fullName.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

/// The login/registration response, mirroring the API `TokenResponse`.
class AuthSession {
  final String accessToken;
  final String tokenType;
  final AppUser user;

  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
