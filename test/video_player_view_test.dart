import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_gallery/widgets/video_player_view.dart';

class RecordingPlatformPlayer extends PlatformPlayer {
  RecordingPlatformPlayer() : super(configuration: const PlayerConfiguration());

  final opened = Completer<void>();
  final nativeHandle = Completer<int>();
  bool? attachedAtOpen;
  bool? playAtOpen;
  Playable? mediaAtOpen;
  bool? logListeningAtDispose;
  bool disposed = false;

  bool get logListening => logController.hasListener;

  @override
  Future<int> get handle => nativeHandle.future;

  @override
  Future<void> open(Playable playable, {bool play = true}) {
    attachedAtOpen = isVideoControllerAttached;
    playAtOpen = play;
    mediaAtOpen = playable;
    state = state.copyWith(playing: play);
    return opened.future;
  }

  @override
  Future<void> dispose() async {
    logListeningAtDispose = logListening;
    await super.dispose();
    disposed = true;
  }
}

void main() {
  testWidgets('attaches controller before open and cancels log before dispose',
      (tester) async {
    final platform = RecordingPlatformPlayer();
    final player = Player(platformPlayer: platform);
    final file = File('/fixture/video.mp4');
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(file: file, playerFactory: () => player),
    ));

    expect(platform.attachedAtOpen, isTrue);
    expect(platform.playAtOpen, isTrue);
    expect((platform.mediaAtOpen as Media).uri, Media(file.path).uri);
    expect(platform.logListening, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Video), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(platform.logListeningAtDispose, isFalse);
    expect(platform.disposed, isTrue);
    platform.opened.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('open failure displays error instead of video', (tester) async {
    final platform = RecordingPlatformPlayer();
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        file: File('/fixture/broken.mp4'),
        playerFactory: () => Player(platformPlayer: platform),
      ),
    ));
    platform.opened.completeError(StateError('open failed'));
    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(Video), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(platform.logListeningAtDispose, isFalse);
    expect(platform.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Linux first-frame timeout retains system-player fallback',
      (tester) async {
    final platform = RecordingPlatformPlayer();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoPlayerView(
          file: File('/fixture/video.mp4'),
          playerFactory: () => Player(platformPlayer: platform),
        ),
      ),
    ));
    platform.opened.complete();
    await tester.pump();
    expect(find.byType(Video), findsOneWidget);
    expect(find.text('Open with system player'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Open with system player'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(platform.logListeningAtDispose, isFalse);
    expect(platform.disposed, isTrue);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isLinux);
}
