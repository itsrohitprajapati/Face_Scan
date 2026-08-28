import 'package:flutter/material.dart';

import '../models/attendance.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} ${d.year} · $hh:$mm';
}

/// Teacher view of one attendance session: the automated per-student result
/// plus the ability to mark a student **present / late / absent** by hand.
///
/// Marking maps to the `a/` route
/// `PATCH /sessions/{id}/attendance/{studentId}`, which the backend only
/// accepts once the session is completed (so live sessions are read-only here).
class SessionAttendanceScreen extends StatefulWidget {
  final AttendanceSession session;
  const SessionAttendanceScreen({super.key, required this.session});

  @override
  State<SessionAttendanceScreen> createState() => _SessionAttendanceScreenState();
}

class _SessionAttendanceScreenState extends State<SessionAttendanceScreen> {
  late Future<List<AttendanceRecord>> _future;
  List<AttendanceRecord> _records = const [];
  final _searchController = TextEditingController();
  String _query = '';

  bool get _editable => widget.session.isCompleted;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AttendanceRecord> get _filteredRecords {
    if (_query.isEmpty) return _records;
    return _records
        .where((r) =>
    r.studentName.toLowerCase().contains(_query) ||
        r.rollNumber.toLowerCase().contains(_query))
        .toList();
  }

  Future<List<AttendanceRecord>> _load() async {
    final records =
    await ApiService.instance.listSessionAttendance(widget.session.id);
    if (mounted) setState(() => _records = records);
    return records;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {}
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

  Future<void> _mark(AttendanceRecord record) async {
    if (!_editable) return;
    final result = await showModalBottomSheet<_MarkResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MarkAttendanceSheet(record: record),
    );
    if (result == null) return;

    try {
      final override = await ApiService.instance.overrideAttendance(
        sessionId: widget.session.id,
        studentId: record.studentId,
        status: result.status,
        reason: result.reason,
      );
      if (!mounted) return;
      setState(() {
        _records = _records
            .map((r) => r.studentId == record.studentId
            ? r.copyWith(
            effectiveStatus: override.status, latestOverride: override)
            : r)
            .toList();
      });
      _snack('${record.studentName} marked ${override.status}');
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Something went wrong: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.session.title)),
      body: RefreshIndicator(
        color: AppColors.green,
        onRefresh: _refresh,
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                _SessionHeader(session: widget.session),
                const SizedBox(height: 16),
                if (_editable)
                  const _EditableNotice()
                else
                  const InlineNotice(
                    'This session is still live. Attendance can be marked once '
                        'you stop the session from the web dashboard.',
                  ),
                const SizedBox(height: 20),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                        child: CircularProgressIndicator(color: AppColors.green)),
                  )
                else if (snapshot.hasError)
                  _ErrorView(
                    message: snapshot.error is ApiException
                        ? '${snapshot.error}'
                        : 'Could not load attendance for this session.',
                    onRetry: _refresh,
                  )
                else ...[
                    _Totals(records: _records),
                    const SizedBox(height: 20),
                    const SectionLabel('Students'),
                    const SizedBox(height: 10),
                    if (_records.isNotEmpty) ...[
                      _SearchField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _query = value.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_records.isEmpty)
                      const _EmptyHint(
                        'No attendance records for this session yet.',
                      )
                    else if (_filteredRecords.isEmpty)
                      _EmptyHint(
                        'No students match "${_searchController.text.trim()}".',
                      )
                    else
                      ..._filteredRecords.map(
                            (record) => _RecordTile(
                          record: record,
                          editable: _editable,
                          onMark: () => _mark(record),
                        ),
                      ),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  final AttendanceSession session;
  const _SessionHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    final location = [
      if (session.roomName != null && session.roomName!.isNotEmpty)
        session.roomName!,
      if (session.roomCode != null && session.roomCode!.isNotEmpty)
        session.roomCode!,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_outlined,
                color: AppColors.green, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  location.isEmpty
                      ? _formatDate(session.startedAt)
                      : '$location · ${_formatDate(session.startedAt)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SessionStatusPill(active: session.isActive),
        ],
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        active ? 'Live' : 'Completed',
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EditableNotice extends StatelessWidget {
  const _EditableNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.touch_app_outlined, color: AppColors.green, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tap a student to mark them present, late or absent. Your '
                  'correction is recorded alongside the automated result.',
              style: TextStyle(
                  color: AppColors.green, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact search field for filtering the student list below by name or
/// roll number. Purely client-side — the records are already loaded.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search by name or roll number',
          prefixIcon: const Icon(Icons.search, color: AppColors.muted, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close, color: AppColors.muted, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              );
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  final List<AttendanceRecord> records;
  const _Totals({required this.records});

  int _count(String status) =>
      records.where((r) => r.effectiveStatus == status).length;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetricCard(
            label: 'Present',
            value: '${_count('present')}',
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            label: 'Late',
            value: '${_count('late')}',
            icon: Icons.schedule,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            label: 'Absent',
            value: '${_count('absent')}',
            icon: Icons.cancel_outlined,
          ),
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  final AttendanceRecord record;
  final bool editable;
  final VoidCallback onMark;
  const _RecordTile({
    required this.record,
    required this.editable,
    required this.onMark,
  });

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
          onTap: editable ? onMark : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.greenSoft,
                  child: Text(
                    record.initials,
                    style: const TextStyle(
                        color: AppColors.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.studentName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        'Roll ${record.rollNumber} · '
                            '${record.observedWindows}/${record.eligibleWindows} min '
                            '(${record.presencePercentage.toStringAsFixed(0)}%)',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (record.isOverridden) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Marked by ${record.latestOverride!.teacherName}',
                          style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusBadge(record.effectiveStatus),
                    if (editable) ...[
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 13, color: AppColors.green),
                          SizedBox(width: 3),
                          Text('Mark',
                              style: TextStyle(
                                  color: AppColors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Result returned by [_MarkAttendanceSheet] when the teacher confirms.
class _MarkResult {
  final String status;
  final String reason;
  const _MarkResult(this.status, this.reason);
}

/// Bottom sheet to pick present / late / absent (plus an optional reason) for
/// one student.
class _MarkAttendanceSheet extends StatefulWidget {
  final AttendanceRecord record;
  const _MarkAttendanceSheet({required this.record});

  @override
  State<_MarkAttendanceSheet> createState() => _MarkAttendanceSheetState();
}

class _MarkAttendanceSheetState extends State<_MarkAttendanceSheet> {
  late String _status = widget.record.effectiveStatus;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mark ${widget.record.studentName}',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text('Automated result: ${widget.record.automatedStatus}',
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 18),
          Row(
            children: [
              _StatusChoice(
                label: 'Present',
                status: 'present',
                selected: _status == 'present',
                onTap: () => setState(() => _status = 'present'),
              ),
              const SizedBox(width: 10),
              _StatusChoice(
                label: 'Late',
                status: 'late',
                selected: _status == 'late',
                onTap: () => setState(() => _status = 'late'),
              ),
              const SizedBox(width: 10),
              _StatusChoice(
                label: 'Absent',
                status: 'absent',
                selected: _status == 'absent',
                onTap: () => setState(() => _status = 'absent'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Reason (optional)',
            controller: _reason,
            hintText: 'e.g. Was present but camera missed them',
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .pop(_MarkResult(_status, _reason.text)),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChoice extends StatelessWidget {
  final String label;
  final String status;
  final bool selected;
  final VoidCallback onTap;
  const _StatusChoice({
    required this.label,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    late final Color fg;
    late final Color bg;
    switch (status) {
      case 'present':
        fg = AppColors.green;
        bg = AppColors.greenSoft;
        break;
      case 'late':
        fg = AppColors.orange;
        bg = AppColors.orangeSoft;
        break;
      default:
        fg = AppColors.red;
        bg = AppColors.redSoft;
    }
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? bg : AppColors.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? fg : AppColors.line,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                status == 'present'
                    ? Icons.check_circle_outline
                    : status == 'late'
                    ? Icons.schedule
                    : Icons.cancel_outlined,
                color: selected ? fg : AppColors.muted,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? fg : AppColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
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