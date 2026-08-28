import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/attendance.dart';
import '../models/camera_source.dart';
import '../models/classroom.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'session_attendance_screen.dart';

const _windowOptions = <num>[0.25, 0.5, 1, 2, 5, 10, 15, 30, 60];

String _formatWindow(num minutes) {
  if (minutes < 1) return '${(minutes * 60).round()} sec';
  if (minutes == 1) return '1 minute';
  return '${minutes.toInt()} minutes';
}

/// Teacher screen for a class's live camera feed and session control —
/// the mobile counterpart of the web app's "Live setup" tab.
///
/// On open it checks whether the class already has an active session
/// (`GET /classes/{id}/sessions`); if so it jumps straight to the live feed,
/// otherwise it shows the start-session form. Starting hits
/// `POST /classes/{id}/sessions`, the feed polls
/// `GET /sessions/{id}/cameras/{id}/preview`, and stopping hits
/// `POST /sessions/{id}/stop` before handing off to [SessionAttendanceScreen].
class LiveSessionScreen extends StatefulWidget {
  final Classroom classroom;
  const LiveSessionScreen({super.key, required this.classroom});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  bool _bootstrapping = true;
  bool _starting = false;
  bool _stopping = false;
  String? _error;

  AttendanceSession? _activeSession;
  List<CameraSource> _cameras = const [];
  CameraSource? _selectedCamera;
  Uint8List? _frameBytes;
  String? _frameNotice;
  List<Sighting> _sightings = const [];

  Timer? _frameTimer;
  Timer? _sightingsTimer;
  bool _frameInFlight = false;

  final _titleController = TextEditingController(text: 'Morning attendance');
  final _roomCodeController = TextEditingController();
  num _windowMinutes = 1;
  int _graceMinutes = 10;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _sightingsTimer?.cancel();
    _titleController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _error = null;
    });
    try {
      final sessions =
      await ApiService.instance.listClassSessions(widget.classroom.id);
      AttendanceSession? active;
      for (final session in sessions) {
        if (session.isActive) {
          active = session;
          break;
        }
      }
      final rememberedRoomCode = active?.roomCode ??
          (sessions.isNotEmpty ? sessions.first.roomCode : null);
      if (rememberedRoomCode != null && rememberedRoomCode.isNotEmpty) {
        _roomCodeController.text = rememberedRoomCode;
        await _loadCameras(rememberedRoomCode, silent: true);
      }
      if (!mounted) return;
      setState(() => _activeSession = active);
      if (active != null) _startPolling();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load this class\'s sessions.');
    } finally {
      if (mounted) setState(() => _bootstrapping = false);
    }
  }

  Future<void> _loadCameras(String roomCode, {bool silent = false}) async {
    try {
      final cameras = await ApiService.instance.listTeacherRoomCameras(roomCode);
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        final previouslySelectedId = _selectedCamera?.id;
        CameraSource? stillAvailable;
        if (previouslySelectedId != null) {
          for (final c in cameras) {
            if (c.id == previouslySelectedId) {
              stillAvailable = c;
              break;
            }
          }
        }
        _selectedCamera =
            stillAvailable ?? (cameras.isNotEmpty ? cameras.first : null);
      });
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() => _error = e.message);
    }
  }

  void _startPolling() {
    _frameTimer?.cancel();
    _sightingsTimer?.cancel();
    _frameBytes = null;
    _frameTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) => _loadFrame());
    _sightingsTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _loadSightings());
    _loadFrame();
    _loadSightings();
  }

  void _stopPolling() {
    _frameTimer?.cancel();
    _sightingsTimer?.cancel();
    _frameTimer = null;
    _sightingsTimer = null;
  }

  Future<void> _loadFrame() async {
    final session = _activeSession;
    final camera = _selectedCamera;
    if (session == null || camera == null || _frameInFlight) return;
    _frameInFlight = true;
    try {
      final bytes =
      await ApiService.instance.previewCameraFrame(session.id, camera.id);
      if (!mounted) return;
      setState(() {
        _frameBytes = bytes;
        _frameNotice = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // A 404 just means no frame has landed yet — keep the "waiting" hint
      // rather than surfacing it as an error.
      if (e.statusCode != 404) setState(() => _frameNotice = e.message);
    } catch (_) {
      // Transient network hiccups shouldn't interrupt polling.
    } finally {
      _frameInFlight = false;
    }
  }

  Future<void> _loadSightings() async {
    final session = _activeSession;
    if (session == null) return;
    try {
      final sightings = await ApiService.instance.listSessionSightings(session.id);
      if (!mounted) return;
      setState(() => _sightings = sightings.take(8).toList());
    } catch (_) {
      // Best-effort; the feed itself is the primary signal.
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    final title = _titleController.text.trim();
    final roomCode = _roomCodeController.text.trim();
    if (title.isEmpty || roomCode.isEmpty) {
      setState(() => _error = 'Enter a session title and room code to start.');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final cameras = await ApiService.instance.listTeacherRoomCameras(roomCode);
      final session = await ApiService.instance.startSession(
        classId: widget.classroom.id,
        title: title,
        roomCode: roomCode,
        qualificationWindowMinutes: _windowMinutes,
        gracePeriodMinutes: _graceMinutes,
      );
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        // Keep whatever the teacher already picked in the source dropdown,
        // as long as it still exists in the freshly-fetched camera list —
        // don't silently override it with cameras.first.
        final previouslySelectedId = _selectedCamera?.id;
        CameraSource? stillAvailable;
        if (previouslySelectedId != null) {
          for (final c in cameras) {
            if (c.id == previouslySelectedId) {
              stillAvailable = c;
              break;
            }
          }
        }
        _selectedCamera =
            stillAvailable ?? (cameras.isNotEmpty ? cameras.first : null);
        _activeSession = session;
      });
      _startPolling();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to start session.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _selectCamera(CameraSource? camera) {
    setState(() {
      _selectedCamera = camera;
      _frameBytes = null;
    });
  }

  Future<void> _stop() async {
    final session = _activeSession;
    if (session == null || _stopping) return;
    setState(() {
      _stopping = true;
      _error = null;
    });
    try {
      final completed = await ApiService.instance.stopSession(session.id);
      _stopPolling();
      if (!mounted) return;
      // Hand off to the results screen; attendance was just calculated.
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(builder: (_) => SessionAttendanceScreen(session: completed)),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to stop session.');
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeSession;
    return Scaffold(
      appBar: AppBar(
        title: Text(active != null ? 'Live · ${widget.classroom.name}' : 'Start live session'),
      ),
      body: _bootstrapping
          ? const Center(child: CircularProgressIndicator(color: AppColors.green))
          : RefreshIndicator(
        color: AppColors.green,
        onRefresh: _bootstrap,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (_error != null) ...[
              InlineNotice(_error!, isError: true),
              const SizedBox(height: 16),
            ],
            if (active != null) ...[
              _LiveFeedCard(
                active: true,
                cameras: _cameras,
                selectedCamera: _selectedCamera,
                frameBytes: _frameBytes,
                notice: _frameNotice,
                onCameraChanged: _selectCamera,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(active.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, color: AppColors.green)),
                          const SizedBox(height: 2),
                          Text(
                            'Recognition workers are watching enabled sources.',
                            style: TextStyle(
                                color: AppColors.green.withValues(alpha: 0.8), fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _stopping ? null : _stop,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                  icon: _stopping
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.stop_circle_outlined),
                  label: Text(_stopping ? 'Stopping…' : 'Stop and calculate attendance'),
                ),
              ),
              const SizedBox(height: 24),
              const SectionLabel('Recent detections'),
              const SizedBox(height: 10),
              if (_sightings.isEmpty)
                const _EmptyHint('Waiting for face detections…')
              else
                ..._sightings.map((s) => _SightingTile(sighting: s)),
            ] else ...[
              _LiveFeedCard(
                active: false,
                cameras: _cameras,
                selectedCamera: _selectedCamera,
                frameBytes: null,
                notice: null,
                onCameraChanged: _selectCamera,
              ),
              const SizedBox(height: 20),
              const SectionLabel('Session control'),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Session title',
                controller: _titleController,
                hintText: 'Morning attendance',
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Room number or code',
                controller: _roomCodeController,
                hintText: 'Room 204 or RM204X7K2',
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) _loadCameras(value.trim());
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _LabeledDropdown<num>(
                      label: 'Attendance window',
                      value: _windowMinutes,
                      items: _windowOptions,
                      labelBuilder: _formatWindow,
                      onChanged: (v) => setState(() => _windowMinutes = v ?? _windowMinutes),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _GraceMinutesField(
                      value: _graceMinutes,
                      onChanged: (v) => setState(() => _graceMinutes = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _starting ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.play_circle_outline),
                  label: Text(_starting ? 'Starting…' : 'Start recognition session'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The camera preview panel — mirrors the web app's `TeacherCameraPreview`,
/// including the source picker and the green/red recognized-vs-unknown key.
class _LiveFeedCard extends StatelessWidget {
  final bool active;
  final List<CameraSource> cameras;
  final CameraSource? selectedCamera;
  final Uint8List? frameBytes;
  final String? notice;
  final void Function(CameraSource?)? onCameraChanged;

  const _LiveFeedCard({
    required this.active,
    required this.cameras,
    required this.selectedCamera,
    required this.frameBytes,
    required this.notice,
    required this.onCameraChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabledCameras = cameras.where((c) => c.isEnabled).toList();
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
              const Text('Camera feed',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? AppColors.green : AppColors.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(active ? 'Live' : 'Standby',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? AppColors.green : AppColors.muted,
                      )),
                ],
              ),
            ],
          ),
          if (enabledCameras.length > 1) ...[
            const SizedBox(height: 12),
            _LabeledDropdown<CameraSource>(
              label: 'View source',
              value: selectedCamera,
              items: enabledCameras,
              labelBuilder: (c) => '${c.label} · ${c.sourceTypeLabel}',
              onChanged: onCameraChanged,
            ),
          ],
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: const Color(0xFF17201C),
                alignment: Alignment.center,
                child: frameBytes != null
                    ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(frameBytes!, fit: BoxFit.contain, gaplessPlayback: true),
                    if (selectedCamera != null)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _FrameTag(
                            '${selectedCamera!.label} · ${selectedCamera!.sourceTypeLabel}'),
                      ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _FrameTag.rich(
                        const [
                          TextSpan(text: 'Green', style: TextStyle(color: Color(0xFF65D281))),
                          TextSpan(text: ' recognized · '),
                          TextSpan(text: 'Red', style: TextStyle(color: Color(0xFFFF8B8B))),
                          TextSpan(text: ' unknown'),
                        ],
                      ),
                    ),
                  ],
                )
                    : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    notice ??
                        (selectedCamera == null
                            ? 'Enter a room code to load its cameras.'
                            : active
                            ? 'Waiting for ${selectedCamera!.label}. Check that its ${selectedCamera!.sourceTypeLabel} address is reachable from the API server.'
                            : 'Start a session to view the camera feed.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB8C5BC), fontSize: 12.5, height: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameTag extends StatelessWidget {
  final String? text;
  final List<InlineSpan>? spans;
  const _FrameTag(this.text) : spans = null;
  const _FrameTag.rich(this.spans) : text = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF17201C).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: text != null
          ? Text(text!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))
          : RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white, fontSize: 10),
          children: spans,
        ),
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final void Function(T?)? onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              onChanged: onChanged,
              items: items
                  .map((item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item), overflow: TextOverflow.ellipsis),
              ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _GraceMinutesField extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;
  const _GraceMinutesField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ARRIVAL GRACE',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
              ),
              Expanded(
                child: Text('$value min', textAlign: TextAlign.center),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: value < 120 ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SightingTile extends StatelessWidget {
  final Sighting sighting;
  const _SightingTile({required this.sighting});

  @override
  Widget build(BuildContext context) {
    final hh = sighting.matchedAt.hour.toString().padLeft(2, '0');
    final mm = sighting.matchedAt.minute.toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              sighting.studentName,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: sighting.isUnknown ? AppColors.red : AppColors.ink,
              ),
            ),
          ),
          Text('$hh:$mm', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
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
      child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
    );
  }
}