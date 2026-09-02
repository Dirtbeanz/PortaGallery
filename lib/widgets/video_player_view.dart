import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlayerView extends StatefulWidget {
  final File file;

  const VideoPlayerView({super.key, required this.file});

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
        child: Icon(Icons.broken_image_outlined,
            color: Colors.white54, size: 64),
      );
    }
    if (!_ready) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Video(
            controller: _controller,
            controls: NoVideoControls,
            fill: Colors.black,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _player.playOrPause(),
            child: StreamBuilder<bool>(
              stream: _player.stream.playing,
              initialData: true,
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return AnimatedOpacity(
                  opacity: playing ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.0),
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                    child: Icon(
                      playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      color: Colors.white,
                      size: 80,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}