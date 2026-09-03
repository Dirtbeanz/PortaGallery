import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlayerView extends StatefulWidget {
  final File file;
  final VoidCallback? onTap;

  const VideoPlayerView({super.key, required this.file, this.onTap});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  bool _ready = false;
  bool _error = false;

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
    } catch (_) {
      if (mounted) setState(() => _error = true);
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
        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
      );
    }
    if (!_ready) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Video(
      controller: _controller,
      controls: (state) => _PortaVideoControls(
        player: _player,
        onTap: widget.onTap,
      ),
      fill: Colors.black,
      fit: BoxFit.contain,
      // Avoid wakelock/background handling on desktop, where the plugins are
      // not available and can crash.
      wakelock: Platform.isAndroid,
      pauseUponEnteringBackgroundMode: Platform.isAndroid,
    );
  }
}

class _PortaVideoControls extends StatefulWidget {
  final Player player;
  final VoidCallback? onTap;

  const _PortaVideoControls({required this.player, this.onTap});

  @override
  State<_PortaVideoControls> createState() => _PortaVideoControlsState();
}

class _PortaVideoControlsState extends State<_PortaVideoControls> {
  bool _visible = true;
  bool _dragging = false;
  double _dragValue = 0;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
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
      child: StreamBuilder<Duration>(
        stream: widget.player.stream.position,
        initialData: Duration.zero,
        builder: (context, posSnapshot) {
          final position = posSnapshot.data ?? Duration.zero;
          return StreamBuilder<Duration>(
            stream: widget.player.stream.duration,
            initialData: Duration.zero,
            builder: (context, durSnapshot) {
              final duration = durSnapshot.data ?? Duration.zero;
              final maxSeconds = duration.inSeconds > 0
                  ? duration.inSeconds.toDouble()
                  : 1.0;
              final current = _dragging
                  ? _dragValue
                  : position.inSeconds
                      .clamp(0, maxSeconds.round())
                      .toDouble();

              return Row(
                children: [
                  StreamBuilder<bool>(
                    stream: widget.player.stream.playing,
                    initialData: false,
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        tooltip: playing ? 'Pause' : 'Play',
                        onPressed: () {
                          widget.player.playOrPause();
                          _scheduleAutoHide();
                        },
                      );
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
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12),
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
                          widget.player
                              .seek(Duration(seconds: v.round()));
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
                  StreamBuilder<double>(
                    stream: widget.player.stream.volume,
                    initialData: 100,
                    builder: (context, snapshot) {
                      final muted = (snapshot.data ?? 100) <= 0;
                      return IconButton(
                        icon: Icon(
                          muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                        ),
                        tooltip: muted ? 'Unmute' : 'Mute',
                        onPressed: () {
                          widget.player.setVolume(muted ? 100 : 0);
                          _scheduleAutoHide();
                        },
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
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