import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/app_user.dart';
import '../models/classroom.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_gate.dart';
import 'class_detail_screen.dart';

class TeacherHomeScreen extends StatefulWidget {
  final AppUser user;
  const TeacherHomeScreen({super.key, required this.user});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  late Future<List<Classroom>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.listClasses();
  }

  Future<void> _refresh() async {
    final future = ApiService.instance.listClasses();
    setState(() {
      _future = future;
    });
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

  Future<void> _createClass() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _CreateClassSheet(),
    );
    if (created == true) {
      _snack('Class created');
      await _refresh();
    }
  }

  Future<void> _openClass(Classroom classroom) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ClassDetailScreen(classroom: classroom)),
    );
    if (deleted == true) {
      _snack('Class deleted');
      await _refresh();
    }
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createClass,
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New class'),
      ),
      body: RefreshIndicator(
        color: AppColors.green,
        onRefresh: _refresh,
        child: FutureBuilder<List<Classroom>>(
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
                      : 'Could not load your classes.',
                  onRetry: _refresh,
                ),
              );
            }
            final classes = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                const _WebNotice(),
                const SizedBox(height: 20),
                const SectionLabel('Your classes'),
                const SizedBox(height: 10),
                if (classes.isEmpty)
                  const _EmptyHint(
                      'No classes yet. Tap "New class" to create one and share '
                      'its join code with students.')
                else
                  ...classes.map((c) => _ClassCard(
                        classroom: c,
                        onOpen: () => _openClass(c),
                        onCopy: () {
                          Clipboard.setData(ClipboardData(text: c.joinCode));
                          _snack('Join code ${c.joinCode} copied');
                        },
                      )),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WebNotice extends StatelessWidget {
  const _WebNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orangeSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.orange, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tap a class to see its roster and each student\'s attendance, or '
              'to delete it. Live attendance sessions, camera feeds and reports '
              'run in the web dashboard.',
              style: TextStyle(color: AppColors.orange, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final Classroom classroom;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  const _ClassCard({
    required this.classroom,
    required this.onCopy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                      child: const Icon(Icons.class_outlined,
                          color: AppColors.green, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(classroom.name,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                          if (classroom.section != null &&
                              classroom.section!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(classroom.section!,
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 12.5)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ],
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: onCopy,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.vpn_key_outlined,
                            size: 16, color: AppColors.muted),
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
          ),
        ),
      ),
    );
  }
}

class _CreateClassSheet extends StatefulWidget {
  const _CreateClassSheet();

  @override
  State<_CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends State<_CreateClassSheet> {
  final _name = TextEditingController();
  final _section = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _section.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a class name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.instance.createClass(_name.text, _section.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          const Text('New class',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Class name',
            controller: _name,
            hintText: 'e.g. Data Structures',
            enabled: !_saving,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Section (optional)',
            controller: _section,
            hintText: 'e.g. B',
            textInputAction: TextInputAction.done,
            enabled: !_saving,
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            InlineNotice(_error!, isError: true),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Create class'),
            ),
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

class _CenteredList extends StatelessWidget {
  final Widget child;
  const _CenteredList({required this.child});

  @override
  Widget build(BuildContext context) {
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
