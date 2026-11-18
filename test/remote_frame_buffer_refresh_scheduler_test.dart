import 'dart:typed_data';

import 'package:dart_rfb/dart_rfb.dart';
import 'package:flutter_rfb/flutter_rfb.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_refresh_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 800;
const int _height = 480;

/// An update made of one [width] x [height] rectangle.
RemoteFrameBufferClientUpdate _update(final int width, final int height) =>
    RemoteFrameBufferClientUpdate(
      rectangles: <RemoteFrameBufferClientUpdateRectangle>[
        RemoteFrameBufferClientUpdateRectangle(
          byteData: ByteData(0),
          encodingType: const RemoteFrameBufferEncodingType.raw(),
          height: height,
          width: width,
          x: 0,
          y: 0,
        ),
      ],
    );

/// A screen change: the whole screen.
final RemoteFrameBufferClientUpdate _screenChange = _update(_width, _height);

/// An animation: 10 % of the screen.
final RemoteFrameBufferClientUpdate _animation = _update(_width, _height ~/ 10);

void main() {
  late int refreshes;
  late RemoteFrameBufferRefreshScheduler scheduler;

  RemoteFrameBufferRefreshScheduler create({
    final Duration? fullRefreshInterval,
    final Duration? refreshAfterChange,
  }) =>
      scheduler = RemoteFrameBufferRefreshScheduler(
        fullRefreshInterval: fullRefreshInterval,
        refreshAfterChange: refreshAfterChange,
        requestFullUpdate: () => refreshes++,
      )..start();

  void receive(final RemoteFrameBufferClientUpdate update) =>
      scheduler.onUpdate(
        update: update,
        frameBufferWidth: _width,
        frameBufferHeight: _height,
      );

  setUp(() => refreshes = 0);

  test('a screen change covers at least 20 % of the screen', () {
    bool isScreenChange(final int height) =>
        RemoteFrameBufferRefreshScheduler.isScreenChange(
          update: _update(_width, height),
          frameBufferWidth: _width,
          frameBufferHeight: _height,
        );
    expect(isScreenChange(_height), isTrue);
    expect(isScreenChange(_height ~/ 5), isTrue);
    expect(isScreenChange(_height ~/ 5 - 1), isFalse);
    // Many small rectangles add up: a Qt 4 screen change is 1500 tiles.
    expect(
      RemoteFrameBufferRefreshScheduler.isScreenChange(
        update: RemoteFrameBufferClientUpdate(
          rectangles: <RemoteFrameBufferClientUpdateRectangle>[
            for (int i = 0; i < 1500; i++)
              RemoteFrameBufferClientUpdateRectangle(
                byteData: ByteData(0),
                encodingType: const RemoteFrameBufferEncodingType.hextile(),
                height: 16,
                width: 16,
                x: 0,
                y: 0,
              ),
          ],
        ),
        frameBufferWidth: _width,
        frameBufferHeight: _height,
      ),
      isTrue,
    );
    expect(
      RemoteFrameBufferRefreshScheduler.isScreenChange(
        update: _screenChange,
        frameBufferWidth: 0,
        frameBufferHeight: 0,
      ),
      isFalse,
    );
  });

  testWidgets('without durations, nothing is ever requested', (
    final WidgetTester tester,
  ) async {
    create();
    expect(scheduler.isActive, isFalse);
    for (int i = 0; i < 10; i++) {
      receive(_screenChange);
      await tester.pump(const Duration(seconds: 10));
    }
    expect(refreshes, 0);
    expect(scheduler.isActive, isFalse);
    scheduler.dispose();
  });

  testWidgets('the periodic refresh', (final WidgetTester tester) async {
    create(fullRefreshInterval: const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 4900));
    expect(refreshes, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(refreshes, 1);
    // Its answers, a screen change each, change nothing.
    receive(_screenChange);
    await tester.pump(const Duration(seconds: 10));
    expect(refreshes, 3);
    scheduler.dispose();
    expect(scheduler.isActive, isFalse);
    await tester.pump(const Duration(minutes: 1));
    expect(refreshes, 3);
  });

  group('refreshAfterChange', () {
    const Duration delay = Duration(seconds: 2);

    testWidgets('one refresh after a screen change, none after its answer', (
      final WidgetTester tester,
    ) async {
      create(refreshAfterChange: delay);
      receive(_screenChange);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(refreshes, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(refreshes, 1);
      // The answer covers the whole screen: it must not loop.
      receive(_screenChange);
      expect(scheduler.isActive, isFalse);
      for (int i = 0; i < 10; i++) {
        receive(_animation);
        await tester.pump(const Duration(seconds: 1));
      }
      expect(refreshes, 1);
      // A real screen change afterwards is refreshed again.
      receive(_screenChange);
      await tester.pump(delay);
      expect(refreshes, 2);
      receive(_screenChange);
      await tester.pump(const Duration(seconds: 10));
      expect(refreshes, 2);
      scheduler.dispose();
    });

    testWidgets('small updates, e.g. an animation, refresh nothing', (
      final WidgetTester tester,
    ) async {
      create(refreshAfterChange: delay);
      for (int i = 0; i < 10; i++) {
        receive(_animation);
        await tester.pump(const Duration(seconds: 1));
      }
      expect(refreshes, 0);
      scheduler.dispose();
    });

    testWidgets('another screen change pushes the refresh back', (
      final WidgetTester tester,
    ) async {
      create(refreshAfterChange: delay);
      receive(_screenChange);
      await tester.pump(const Duration(milliseconds: 1500));
      receive(_screenChange);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(refreshes, 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(refreshes, 1);
      scheduler.dispose();
    });

    testWidgets('a periodic refresh stands for a pending one', (
      final WidgetTester tester,
    ) async {
      create(
        fullRefreshInterval: const Duration(seconds: 3),
        refreshAfterChange: delay,
      );
      await tester.pump(const Duration(milliseconds: 1500));
      receive(_screenChange);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(refreshes, 1, reason: 'the periodic refresh');
      receive(_screenChange); // its answer
      await tester.pump(const Duration(milliseconds: 2900));
      expect(refreshes, 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(refreshes, 2, reason: 'the next periodic refresh only');
      scheduler.dispose();
    });

    testWidgets('dispose cancels a pending refresh', (
      final WidgetTester tester,
    ) async {
      create(
        fullRefreshInterval: const Duration(seconds: 5),
        refreshAfterChange: delay,
      );
      receive(_screenChange);
      expect(scheduler.isActive, isTrue);
      scheduler.dispose();
      expect(scheduler.isActive, isFalse);
      receive(_screenChange);
      scheduler.start();
      expect(scheduler.isActive, isFalse);
      await tester.pump(const Duration(minutes: 1));
      expect(refreshes, 0);
    });
  });

  group('the widget', () {
    test('has every option off by default', () {
      final RemoteFrameBufferWidget widget =
          RemoteFrameBufferWidget(hostName: 'host');
      expect(widget.pipelineUpdateRequests, isTrue);
      expect(widget.fullRefreshInterval, isNull);
      expect(widget.refreshAfterChange, isNull);
    });

    test('keeps the options it is given', () {
      final RemoteFrameBufferWidget widget = RemoteFrameBufferWidget(
        fullRefreshInterval: const Duration(seconds: 30),
        hostName: 'host',
        pipelineUpdateRequests: false,
        refreshAfterChange: const Duration(seconds: 2),
      );
      expect(widget.pipelineUpdateRequests, isFalse);
      expect(widget.fullRefreshInterval, const Duration(seconds: 30));
      expect(widget.refreshAfterChange, const Duration(seconds: 2));
    });

    for (final Duration duration in <Duration>[
      Duration.zero,
      const Duration(seconds: -1),
    ]) {
      test('rejects a duration of $duration', () {
        expect(
          () => RemoteFrameBufferWidget(
            fullRefreshInterval: duration,
            hostName: 'host',
          ),
          throwsArgumentError,
        );
        expect(
          () => RemoteFrameBufferWidget(
            hostName: 'host',
            refreshAfterChange: duration,
          ),
          throwsArgumentError,
        );
      });
    }
  });
}
