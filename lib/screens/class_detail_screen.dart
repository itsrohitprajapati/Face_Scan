import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/attendance.dart';
import '../models/classroom.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'live_session_screen.dart';
import 'session_attendance_screen.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} ${d.year} · $hh:$mm';
}

/// Teacher-only view of a single owned class: roster, per-student attendance,
/// and destructive delete. Backed by the `a/` routes
/// `GET /classes/{id}/students`, `GET /classes/{id}/students/{id}/attendance`
/// and `DELETE /classes/{id}`.
///
/// Pops with `true` when the class was deleted so the caller can refresh.
class ClassDetailScreen extends StatefulWidget {
  final Classroom classroom;
  const ClassDetailScreen({super.key, required this.classroom});

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  late Future<List<ClassStudent>> _future;
  late Future<List<AttendanceSession>> _sessionsFuture;
  bool _deleting = false;
  DateTime? _sessionDateFilter;

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.listClassStudents(widget.classroom.id);
    _sessionsFuture = ApiService.instance.listClassSessions(widget.classroom.id);
  }

  Future<void> _pickSessionDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _sessionDateFilter ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.green,
            onPrimary: Colors.white,
            onSurface: AppColors.ink,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.green),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _sessionDateFilter = picked);
  }

  void _clearSessionDate() => setState(() => _sessionDateFilter = null);

  Future<void> _refresh() async {
    final studentsFuture =
    ApiService.instance.listClassStudents(widget.classroom.id);
    final sessionsFuture =
    ApiService.instance.listClassSessions(widget.classroom.id);
    setState(() {
      _future = studentsFuture;
      _sessionsFuture = sessionsFuture;
    });
    try {
      await Future.wait([studentsFuture, sessionsFuture]);
    } catch (_) {
      // Surfaced by the FutureBuilders; swallow so the spinner stops.
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.red : AppColors.green,
      ),
    );
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.classroom.joinCode));
    _snack('Join code ${widget.classroom.joinCode} copied');
  }

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Delete class?'),
        content: Text(
          'This permanently removes "${widget.classroom.name}", every student '
              'membership, and all session history. This cannot be undone.',
          style: const TextStyle(color: AppColors.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await ApiService.instance.deleteClass(widget.classroom.id);
      if (!mounted) return;
      Navigator.of(context).pop(true); // Tell the teacher dashboard to refresh.
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Something went wrong: $e', isError: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _openStudentAttendance(ClassStudent student) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StudentAttendanceSheet(
        classId: widget.classroom.id,
        student: student,
      ),
    );
  }

  Future<void> _openLiveSession() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LiveSessionScreen(classroom: widget.classroom),
      ),
    );
    // Starting/stopping a session changes both the session list and, once
    // attendance is calculated, the roster's per-student summary.
    await _refresh();
  }

  Future<void> _openSession(AttendanceSession session) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SessionAttendanceScreen(session: session),
      ),
    );
    // Marking a student can change the roster's attendance summary, so refresh
    // once we return.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classroom.name, style: TextStyle(fontSize: 18),),
        actions: [
          if (_deleting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.red),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Delete class',
              icon: const Icon(Icons.delete_outline, color: AppColors.red),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.green,
        onRefresh: _refresh,
        child: FutureBuilder<List<ClassStudent>>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                _ClassSummaryCard(
                  classroom: widget.classroom,
                  onCopy: _copyCode,
                  onLiveSession: _openLiveSession,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _DateFilterButton(
                      selectedDate: _sessionDateFilter,
                      onPickDate: _pickSessionDate,
                      onClearDate: _clearSessionDate,
                    ),
                    const SizedBox(width: 10),
                    const SectionLabel('Attendance sessions'),
                  ],
                ),
                const SizedBox(height: 10),
                _SessionsSection(
                  future: _sessionsFuture,
                  onOpen: _openSession,
                  onRetry: _refresh,
                  selectedDate: _sessionDateFilter,
                ),
                const SizedBox(height: 24),
                const SectionLabel('Enrolled students'),
                const SizedBox(height: 10),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator(color: AppColors.green)),
                  )
                else if (snapshot.hasError)
                  _ErrorView(
                    message: snapshot.error is ApiException
                        ? '${snapshot.error}'
                        : 'Could not load the student roster.',
                    onRetry: _refresh,
                  )
                else if ((snapshot.data ?? const []).isEmpty)
                    const _EmptyHint(
                      'No students have joined yet. Share the join code above so '
                          'they can enroll.',
                    )
                  else
                    ...snapshot.data!.map(
                          (student) => _StudentTile(
                        student: student,
                        onTap: () => _openStudentAttendance(student),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ClassSummaryCard extends StatelessWidget {
  final Classroom classroom;
  final VoidCallback onCopy;
  final VoidCallback onLiveSession;
  const _ClassSummaryCard({
    required this.classroom,
    required this.onCopy,
    required this.onLiveSession,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (classroom.section != null && classroom.section!.isNotEmpty) classroom.section!,
      classroom.teacherName,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.class_outlined, color: AppColors.green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(classroom.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Live session',
                icon: const Icon(Icons.videocam_outlined, color: AppColors.green),
                onPressed: onLiveSession,
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_outlined, size: 16, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Text(
                    classroom.joinCode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.copy, size: 16, color: AppColors.green),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists this class's attendance sessions (newest first) with its own loading,
/// error and empty states so a session-load failure never hides the roster.
/// An optional [selectedDate] narrows the list to sessions started that day.
class _SessionsSection extends StatelessWidget {
  final Future<List<AttendanceSession>> future;
  final void Function(AttendanceSession) onOpen;
  final Future<void> Function() onRetry;
  final DateTime? selectedDate;
  const _SessionsSection({
    required this.future,
    required this.onOpen,
    required this.onRetry,
    required this.selectedDate,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AttendanceSession>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColors.green)),
          );
        }
        if (snapshot.hasError) {
          return _ErrorView(
            message: snapshot.error is ApiException
                ? '${snapshot.error}'
                : 'Could not load attendance sessions.',
            onRetry: onRetry,
          );
        }
        final sessions = snapshot.data ?? const [];
        if (sessions.isEmpty) {
          return const _EmptyHint(
            'No attendance sessions yet. Tap the camera icon above to start a '
                'live session.',
          );
        }
        final filtered = selectedDate == null
            ? sessions
            : sessions
            .where((s) => _isSameDay(s.startedAt, selectedDate!))
            .toList();
        if (filtered.isEmpty) {
          return _EmptyHint(
            'No sessions on ${_formatDate(selectedDate!).split(' · ').first}.',
          );
        }
        return Column(
          children: filtered
              .map((session) =>
              _SessionTile(session: session, onTap: () => onOpen(session)))
              .toList(),
        );
      },
    );
  }
}

/// Compact calendar button, positioned to the left of the "Attendance
/// sessions" label. Shows the picked date and a clear (×) once active.
class _DateFilterButton extends StatelessWidget {
  final DateTime? selectedDate;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  const _DateFilterButton({
    required this.selectedDate,
    required this.onPickDate,
    required this.onClearDate,
  });

  @override
  Widget build(BuildContext context) {
    final active = selectedDate != null;
    return InkWell(
      onTap: onPickDate,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.greenSoft : AppColors.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AppColors.green : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: active ? AppColors.green : AppColors.muted),
            if (active) ...[
              const SizedBox(width: 6),
              Text(
                _formatDate(selectedDate!).split(' · ').first,
                style: const TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: onClearDate,
                borderRadius: BorderRadius.circular(999),
                child: const Icon(Icons.close, size: 14, color: AppColors.green),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final AttendanceSession session;
  final VoidCallback onTap;
  const _SessionTile({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.event_available_outlined,
                      color: AppColors.green, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(_formatDate(session.startedAt),
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _SessionStatusPill(active: session.isActive),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionStatusPill extends StatelessWidget {
  final bool active;
  const _SessionStatusPill({required this.active});

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.orange : AppColors.green;
    final bg = active ? AppColors.orangeSoft : AppColors.greenSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
      BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        active ? 'Live' : 'Completed',
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final ClassStudent student;
  final VoidCallback onTap;
  const _StudentTile({required this.student, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.greenSoft,
                  child: Text(
                    student.initials,
                    style: const TextStyle(
                        color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text('Roll ${student.rollNumber} · ${student.email}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that loads and shows one student's attendance in this class.
class _StudentAttendanceSheet extends StatefulWidget {
  final String classId;
  final ClassStudent student;
  const _StudentAttendanceSheet({required this.classId, required this.student});

  @override
  State<_StudentAttendanceSheet> createState() => _StudentAttendanceSheetState();
}

class _StudentAttendanceSheetState extends State<_StudentAttendanceSheet> {
  late Future<AttendanceSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance
        .studentAttendanceInClass(widget.classId, widget.student.id);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return FutureBuilder<AttendanceSummary>(
          future: _future,
          builder: (context, snapshot) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(widget.student.fullName,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text('Roll ${widget.student.rollNumber}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 20),
                if (snapshot.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: AppColors.green)),
                  )
                else if (snapshot.hasError)
                  InlineNotice(
                    snapshot.error is ApiException
                        ? '${snapshot.error}'
                        : 'Could not load this student\'s attendance.',
                    isError: true,
                  )
                else ...[
                    _Metrics(summary: snapshot.data!),
                    const SizedBox(height: 24),
                    const SectionLabel('Session history'),
                    const SizedBox(height: 10),
                    if (snapshot.data!.history.isEmpty)
                      const _EmptyHint('No completed sessions yet.')
                    else
                      ...snapshot.data!.history.map((e) => _HistoryTile(entry: e)),
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

class _Metrics extends StatelessWidget {
  final AttendanceSummary summary;
  const _Metrics({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: MetricCard(
              label: 'Attendance',
              value: '${summary.attendancePercentage.toStringAsFixed(0)}%',
              icon: Icons.donut_large,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              label: 'Present',
              value: '${summary.presentSessions}',
              icon: Icons.check_circle_outline,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: MetricCard(
              label: 'Late',
              value: '${summary.lateSessions}',
              icon: Icons.schedule,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              label: 'Absent',
              value: '${summary.absentSessions}',
              icon: Icons.cancel_outlined,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Across ${summary.totalSessions} completed session(s).',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final AttendanceHistoryEntry entry;
  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(entry.sessionTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.ink)),
              ),
              StatusBadge(entry.effectiveStatus),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_formatDate(entry.sessionStartedAt)} · '
                '${entry.presencePercentage.toStringAsFixed(0)}% coverage '
                '(${entry.observedWindows}/${entry.eligibleWindows} windows)',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(text,
          style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: AppColors.muted, size: 40),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}