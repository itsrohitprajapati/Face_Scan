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
