import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/external_player_service.dart';

class VideoPlayerView extends StatefulWidget {
  final File file;
  final VoidCallback? onTap;

  const VideoPlayerView({super.key, required this.file, this.onTap});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(
    _player,
    configuration: const VideoControllerConfiguration(
      // FFmpeg-based hardware decoding where available; falls back to
      // software safely. VA-API needs `intel-media-driver` on Intel GPUs.
      hwdec: 'auto-safe',
    ),
  );
  bool _ready = false;
  bool _error = false;
  bool _renderFailed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.open(Media(widget.file.path), play: true);
      if (!mounted) return;
      setState(() => _ready = true);
      _watchFirstFrame();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _watchFirstFrame() async {
    if (!Platform.isLinux) return;
    try {
      await _controller.waitUntilFirstFrameRendered
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      if (mounted && _player.state.playing) {
        setState(() => _renderFailed = true);
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child:
            Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
      );
    }
    if (!_ready) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _controller,
          controls: (state) => _PortaVideoControls(
            player: _player,
            onTap: widget.onTap,
            externalEnabled: Platform.isLinux,
            filePath: widget.file.path,
          ),
          fill: Colors.black,
          fit: BoxFit.contain,
          // Avoid wakelock/background handling on desktop, where the plugins
          // are not available and can crash.
          wakelock: Platform.isAndroid,
          pauseUponEnteringBackgroundMode: Platform.isAndroid,
        ),
        if (_renderFailed)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.slow_motion_video,
                        color: Colors.white70, size: 56),
                    const SizedBox(height: 12),
                    const Text(
                      'In-app video rendering is not available here.',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open with system player'),
                      onPressed: () => _openExternal(),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openExternal() async {
    try {
      await _player.pause();
    } catch (_) {}
    await ExternalPlayerService.launch(widget.file.path);
  }
}

class _PortaVideoControls extends StatefulWidget {
  final Player player;
  final VoidCallback? onTap;
  final bool externalEnabled;
  final String? filePath;

  const _PortaVideoControls({
    required this.player,
    this.onTap,
    this.externalEnabled = false,
    this.filePath,
  });

  @override
  State<_PortaVideoControls> createState() => _PortaVideoControlsState();
}

class _PortaVideoControlsState extends State<_PortaVideoControls> {
  bool _visible = true;
  bool _dragging = false;
  double _dragValue = 0;
  Timer? _hideTimer;
  Timer? _pollTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      final state = widget.player.state;
      if (state.duration != _duration ||
          state.playing != _playing ||
          state.volume <= 0 != _muted ||
          (_position - state.position).abs().inSeconds >= 1) {
        setState(() {
          _duration = state.duration;
          _position = state.position;
          _playing = state.playing;
          _muted = state.volume <= 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _toggleVisibility() {
    widget.onTap?.call();
    setState(() => _visible = !_visible);
    _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    if (_visible) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _visible && !_dragging) {
          setState(() => _visible = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleVisibility,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: StreamBuilder<bool>(
                stream: widget.player.stream.playing,
                initialData: true,
                builder: (context, snapshot) {
                  if (snapshot.data ?? true) return const SizedBox.shrink();
                  return const Icon(Icons.play_circle_fill,
                      color: Colors.white70, size: 72);
                },
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: Platform.isAndroid ? 72 : 24,
              child: _buildControlBar(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: _buildBarRow(context),
    );
  }

  Widget _buildBarRow(BuildContext context) {
    final duration = _duration;
    final position = _position;
    final maxSeconds =
        duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
    final current = _dragging
        ? _dragValue
        : position.inSeconds.clamp(0, maxSeconds.round()).toDouble();

    return Row(
      children: [
        IconButton(
          icon: Icon(
            _playing ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
          ),
          tooltip: _playing ? 'Pause' : 'Play',
          onPressed: () {
            widget.player.playOrPause();
            setState(() => _playing = widget.player.state.playing);
            _scheduleAutoHide();
          },
        ),
        Text(
          _formatDuration(position),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white38,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: current.clamp(0.0, maxSeconds),
              max: maxSeconds,
              onChangeStart: (v) {
                _dragging = true;
                _dragValue = v;
                setState(() {});
              },
              onChanged: (v) {
                setState(() => _dragValue = v);
              },
              onChangeEnd: (v) {
                _dragging = false;
                widget.player.seek(Duration(seconds: v.round()));
                _scheduleAutoHide();
                setState(() {});
              },
            ),
          ),
        ),
        Text(
          _formatDuration(duration),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        IconButton(
          icon: Icon(
            _muted ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
          ),
          tooltip: _muted ? 'Unmute' : 'Mute',
          onPressed: () {
            widget.player.setVolume(_muted ? 100 : 0);
            setState(() => _muted = !_muted);
            _scheduleAutoHide();
          },
        ),
        if (widget.externalEnabled)
          IconButton(
            icon: const Icon(Icons.open_in_new, color: Colors.white),
            tooltip: 'Open with system player',
            onPressed: () async {
              final path = widget.filePath;
              if (path != null) {
                await ExternalPlayerService.launch(path);
              }
              try {
                await widget.player.pause();
              } catch (_) {}
            },
          ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }
}