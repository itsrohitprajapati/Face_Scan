import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/classroom.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_gate.dart';
import 'profile_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  final AppUser user;
  const StudentHomeScreen({super.key, required this.user});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentData {
  final AttendanceSummary summary;
  final List<Classroom> classes;
  const _StudentData(this.summary, this.classes);
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  late Future<_StudentData> _future;
  final _joinCode = TextEditingController();
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _joinCode.dispose();
    super.dispose();
  }

  Future<_StudentData> _load() async {
    final results = await Future.wait([
      ApiService.instance.studentAttendance(),
      ApiService.instance.listClasses(),
    ]);
    return _StudentData(
      results[0] as AttendanceSummary,
      results[1] as List<Classroom>,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // Error surface is handled by the FutureBuilder; swallow so the
      // pull-to-refresh spinner stops.
    }
  }

  Future<void> _join() async {
    final code = _joinCode.text.trim();
    if (code.isEmpty || _joining) return;
    FocusScope.of(context).unfocus();
    setState(() => _joining = true);
    try {
      final classroom = await ApiService.instance.joinClass(code);
      _joinCode.clear();
      _snack('Joined ${classroom.name}');
      await _refresh();
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Something went wrong: $e', isError: true);
    } finally {
      if (mounted) setState(() => _joining = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${widget.user.firstName}'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutTo(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.green,
        onRefresh: _refresh,
        child: FutureBuilder<_StudentData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _CenteredList(
                child: CircularProgressIndicator(color: AppColors.green),
              );
            }
            if (snapshot.hasError) {
              return _CenteredList(
                child: _ErrorView(
                  message: snapshot.error is ApiException
                      ? '${snapshot.error}'
                      : 'Could not load your dashboard.',
                  onRetry: _refresh,
                ),
              );
            }
            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _ProfileCard(
                  user: widget.user,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(user: widget.user),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Attendance'),
                const SizedBox(height: 10),
                _Metrics(summary: data.summary),
                const SizedBox(height: 24),
                const SectionLabel('Join a class'),
                const SizedBox(height: 10),
                _JoinCard(
                  controller: _joinCode,
                  busy: _joining,
                  onJoin: _join,
                ),
                const SizedBox(height: 24),
                const SectionLabel('My classes'),
                const SizedBox(height: 10),
                if (data.classes.isEmpty)
                  const _EmptyHint('You have not joined any classes yet.')
                else
                  ...data.classes.map((c) => _ClassTile(classroom: c)),
                const SizedBox(height: 24),
                const SectionLabel('Session history'),
                const SizedBox(height: 10),
                if (data.summary.history.isEmpty)
                  const _EmptyHint('No completed sessions yet.')
                else
                  ...data.summary.history.map((e) => _HistoryTile(entry: e)),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback? onTap;
  const _ProfileCard({required this.user, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.greenSoft,
              child: Text(
                user.initials,
                style: const TextStyle(
                    color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(
                    user.rollNumber == null
                        ? user.email
                        : 'Roll ${user.rollNumber} · ${user.email}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (user.enrollmentComplete)
              const Icon(Icons.verified, color: AppColors.green),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  final AttendanceSummary summary;
  const _Metrics({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cards = [
      MetricCard(
        label: 'Attendance',
        value: '${summary.attendancePercentage.toStringAsFixed(0)}%',
        icon: Icons.donut_large,
      ),
      MetricCard(
        label: 'Present',
        value: '${summary.presentSessions}',
        icon: Icons.check_circle_outline,
      ),
      MetricCard(
        label: 'Late',
        value: '${summary.lateSessions}',
        icon: Icons.schedule,
      ),
      MetricCard(
        label: 'Absent',
        value: '${summary.absentSessions}',
        icon: Icons.cancel_outlined,
      ),
    ];
    return Column(
      children: [
        Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 12),
          Expanded(child: cards[1]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: cards[2]),
          const SizedBox(width: 12),
          Expanded(child: cards[3]),
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

class _JoinCard extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onJoin;
  const _JoinCard({
    required this.controller,
    required this.busy,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppTextField(
            label: 'Join code',
            controller: controller,
            hintText: 'e.g. AB12CD34',
            textInputAction: TextInputAction.done,
            enabled: !busy,
            onSubmitted: (_) => onJoin(),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: busy ? null : onJoin,
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Join'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ClassTile extends StatelessWidget {
  final Classroom classroom;
  const _ClassTile({required this.classroom});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (classroom.section != null && classroom.section!.isNotEmpty)
        classroom.section!,
      classroom.teacherName,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.class_outlined, color: AppColors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(classroom.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final AttendanceHistoryEntry entry;
  const _HistoryTile({required this.entry});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _date {
    final d = entry.sessionStartedAt;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year} · $hh:$mm';
  }

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
                child: Text(entry.className,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: AppColors.ink)),
              ),
              StatusBadge(entry.effectiveStatus),
            ],
          ),
          const SizedBox(height: 4),
          Text(entry.sessionTitle,
              style: const TextStyle(color: AppColors.ink, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            '$_date · ${entry.presencePercentage.toStringAsFixed(0)}% coverage '
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
          style: const TextStyle(color: AppColors.muted, fontSize: 13)),
    );
  }
}

class _CenteredList extends StatelessWidget {
  final Widget child;
  const _CenteredList({required this.child});

  @override
  Widget build(BuildContext context) {
    // Always scrollable so RefreshIndicator works even while loading/erroring.
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(child: child),
        ),
      ],
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
      padding: const EdgeInsets.all(24),
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
