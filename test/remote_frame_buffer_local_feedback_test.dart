import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/widgets.dart' hide Image;
import 'package:flutter_rfb/flutter_rfb.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_isolate_messages.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_local_feedback.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_pointer_listener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;

/// A remote screen of 4x2 pixels shown in a 40x20 widget: one remote pixel
/// is 10x10 logical pixels.
const Size _widgetSize = Size(40, 20);

/// A 2x3 cursor whose hotspot is its bottom right pixel.
const int _hotspotX = 1;
const int _hotspotY = 2;

Future<Image> _cursorImage(final WidgetTester tester) async =>
    (await tester.runAsync(() => createTestImage(width: 2, height: 3)))!;

Widget _build({
  required final Option<Image> cursorImage,
  final bool withCursor = true,
  final MouseCursor fallbackCursor = SystemMouseCursors.basic,
  final bool pressFeedback = true,
  final Size size = _widgetSize,
  final double parentScale = 1,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Transform.scale(
          alignment: Alignment.topLeft,
          scale: parentScale,
          child: SizedBox.fromSize(
            size: size,
            child: RemoteFrameBufferLocalFeedback(
              cursor: withCursor
                  ? some(
                      RemoteFrameBufferCursorImage(
                        image: cursorImage,
                        hotspotX: _hotspotX,
                        hotspotY: _hotspotY,
                      ),
                    )
                  : none(),
              fallbackCursor: fallbackCursor,
              frameBufferHeight: 2,
              frameBufferWidth: 4,
              pressFeedback: pressFeedback,
              pressFeedbackColor: const Color(0xFF2196F3),
              // Hit-testable, as the pointer listener is in the real tree.
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );

RemoteFrameBufferLocalFeedbackState _state(final WidgetTester tester) =>
    tester.state<RemoteFrameBufferLocalFeedbackState>(
      find.byType(RemoteFrameBufferLocalFeedback),
    );

/// The cursor the mouse (device 1, the default of mouse gestures) shows.
MouseCursor? _activeCursor() =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

Future<TestGesture> _mouseAt(
  final WidgetTester tester,
  final Offset position,
) async {
  final TestGesture mouse =
      await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: position);
  addTearDown(mouse.removePointer);
  await tester.pump();
  return mouse;
}

void main() {
  group('local cursor', () {
    testWidgets('is drawn with its hotspot at the mouse', (
      final WidgetTester tester,
    ) async {
      final Image image = await _cursorImage(tester);
      addTearDown(image.dispose);
      await tester.pumpWidget(_build(cursorImage: some(image)));
      final TestGesture mouse = await _mouseAt(tester, const Offset(15, 12));
      // One cursor pixel per remote pixel: 10x10 logical pixels.
      expect(_state(tester).cursorRect, const Rect.fromLTWH(5, -8, 20, 30));
      await mouse.moveTo(const Offset(25, 18));
      await tester.pump();
      expect(_state(tester).cursorRect, const Rect.fromLTWH(15, -2, 20, 30));
    });

    testWidgets('follows the framebuffer scale', (
      final WidgetTester tester,
    ) async {
      final Image image = await _cursorImage(tester);
      addTearDown(image.dispose);
      // 100x40 for a 4x2 framebuffer: scale 20, the image is centered.
      await tester.pumpWidget(
        _build(cursorImage: some(image), size: const Size(100, 40)),
      );
      await _mouseAt(tester, const Offset(50, 30));
      expect(_state(tester).cursorRect, const Rect.fromLTWH(30, -10, 40, 60));
    });

    testWidgets('uses local coordinates inside a zoomed parent', (
      final WidgetTester tester,
    ) async {
      final Image image = await _cursorImage(tester);
      addTearDown(image.dispose);
      // As inside an InteractiveViewer zoomed twice.
      await tester.pumpWidget(
        _build(cursorImage: some(image), parentScale: 2),
      );
      await _mouseAt(tester, const Offset(30, 24));
      expect(_state(tester).cursorRect, const Rect.fromLTWH(5, -8, 20, 30));
    });

    testWidgets('hides the system cursor while a visible shape is drawn', (
      final WidgetTester tester,
    ) async {
      final Image image = await _cursorImage(tester);
      addTearDown(image.dispose);
      await tester.pumpWidget(_build(cursorImage: some(image)));
      await _mouseAt(tester, const Offset(15, 12));
      expect(_activeCursor(), SystemMouseCursors.none);
      expect(_state(tester).cursorRect, isNotNull);
    });

    testWidgets('shows the fallback cursor before any shape arrives', (
      final WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _build(cursorImage: none(), withCursor: false),
      );
      await _mouseAt(tester, const Offset(15, 12));
      expect(_activeCursor(), SystemMouseCursors.basic);
      expect(_state(tester).cursorRect, isNull);
    });

    testWidgets('an invisible (0x0) shape shows the fallback cursor', (
      final WidgetTester tester,
    ) async {
      await tester.pumpWidget(_build(cursorImage: none()));
      await _mouseAt(tester, const Offset(15, 12));
      expect(_state(tester).cursorRect, isNull);
      expect(_activeCursor(), SystemMouseCursors.basic);
    });

    testWidgets('follows visible and invisible shapes while hovering', (
      final WidgetTester tester,
    ) async {
      final Image image = await _cursorImage(tester);
      addTearDown(image.dispose);
      await tester.pumpWidget(_build(cursorImage: some(image)));
      // The mouse stays over the widget from here on.
      await _mouseAt(tester, const Offset(15, 12));
      expect(_activeCursor(), SystemMouseCursors.none);
      await tester.pumpWidget(_build(cursorImage: none()));
      expect(_activeCursor(), SystemMouseCursors.basic);
      expect(_state(tester).cursorRect, isNull);
      await tester.pumpWidget(_build(cursorImage: some(image)));
      expect(_activeCursor(), SystemMouseCursors.none);
      expect(_state(tester).cursorRect, const Rect.fromLTWH(5, -8, 20, 30));
    });

    testWidgets('the fallback cursor can be chosen', (
      final WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _build(
          cursorImage: none(),
          fallbackCursor: SystemMouseCursors.precise,
        ),
      );
      await _mouseAt(tester, const Offset(15, 12));
      expect(_activeCursor(), SystemMouseCursors.precise);
    });

    testWidgets('is not drawn for touch input', (
      final WidgetTester tester,
    ) async {
      final Image image = await _cursorImage(tester);
      addTearDown(image.dispose);
      await tester.pumpWidget(_build(cursorImage: some(image)));
      await _mouseAt(tester, const Offset(15, 12));
      expect(_state(tester).cursorRect, isNotNull);
      final TestGesture touch = await tester.startGesture(
        const Offset(25, 5),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(_state(tester).cursorRect, isNull);
      await touch.moveTo(const Offset(30, 8));
      await tester.pump();
      expect(_state(tester).cursorRect, isNull);
      await touch.up();
      await tester.pumpAndSettle();
    });

    testWidgets('disappears when the mouse leaves the widget', (
      final WidgetTester tester,
    ) async {
      final Image image = await _cursorImage(tester);
      addTearDown(image.dispose);
      await tester.pumpWidget(_build(cursorImage: some(image)));
      final TestGesture mouse = await _mouseAt(tester, const Offset(15, 12));
      await mouse.moveTo(const Offset(200, 200));
      await tester.pump();
      expect(_state(tester).cursorRect, isNull);
    });

    testWidgets('is not drawn without a remote cursor', (
      final WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _build(cursorImage: none(), withCursor: false),
      );
      await _mouseAt(tester, const Offset(15, 12));
      expect(_state(tester).cursorRect, isNull);
    });
  });

  group('press feedback', () {
    const Duration duration =
        RemoteFrameBufferLocalFeedback.pressFeedbackDuration;

    for (final PointerDeviceKind kind in <PointerDeviceKind>[
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
    ]) {
      testWidgets('a ${kind.name} press shows a halo that fades out', (
        final WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          _build(cursorImage: none(), withCursor: false),
        );
        final TestGesture gesture =
            await tester.startGesture(const Offset(15, 12), kind: kind);
        await tester.pump();
        expect(_state(tester).haloCount, 1);
        await tester.pump(duration - const Duration(milliseconds: 20));
        expect(_state(tester).haloCount, 1);
        await tester.pump(const Duration(milliseconds: 40));
        expect(_state(tester).haloCount, 0);
        await gesture.up();
        await tester.pump();
      });
    }

    testWidgets('a drag keeps a single halo', (
      final WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _build(cursorImage: none(), withCursor: false),
      );
      final TestGesture touch = await tester.startGesture(
        const Offset(5, 5),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await touch.moveTo(const Offset(35, 15));
      await tester.pump();
      expect(_state(tester).haloCount, 1);
      await touch.up();
      await tester.pumpAndSettle();
      expect(_state(tester).haloCount, 0);
    });

    testWidgets('can be disabled', (final WidgetTester tester) async {
      await tester.pumpWidget(
        _build(cursorImage: none(), withCursor: false, pressFeedback: false),
      );
      await tester.tapAt(const Offset(15, 12));
      await tester.pump();
      expect(_state(tester).haloCount, 0);
    });
  });

  testWidgets('presses still reach the pointer listener below', (
    final WidgetTester tester,
  ) async {
    final Image image = await _cursorImage(tester);
    addTearDown(image.dispose);
    final Image frameBuffer =
        (await tester.runAsync(() => createTestImage(width: 4, height: 2)))!;
    addTearDown(frameBuffer.dispose);
    final ReceivePort port = ReceivePort();
    addTearDown(port.close);
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> received =
        <RemoteFrameBufferIsolateSendMessagePointerEvent>[];
    port.listen((final Object? message) {
      if (message is RemoteFrameBufferIsolateSendMessagePointerEvent) {
        received.add(message);
      }
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: _widgetSize,
            child: RemoteFrameBufferLocalFeedback(
              cursor: some(
                RemoteFrameBufferCursorImage(
                  image: some(image),
                  hotspotX: _hotspotX,
                  hotspotY: _hotspotY,
                ),
              ),
              fallbackCursor: SystemMouseCursors.basic,
              frameBufferHeight: 2,
              frameBufferWidth: 4,
              pressFeedback: true,
              pressFeedbackColor: const Color(0xFF2196F3),
              child: RemoteFrameBufferPointerListener(
                image: frameBuffer,
                remoteFrameBufferWidgetSize: _widgetSize,
                sendPort: some(port.sendPort),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      const Offset(25, 15),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(_state(tester).haloCount, 1);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(received, hasLength(1));
    expect(received.single.button1Down, isTrue);
    expect((received.single.x, received.single.y), (2, 1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  group('RemoteFrameBufferWidget options', () {
    test('local cursor and press feedback are on, with an arrow fallback', () {
      final RemoteFrameBufferWidget widget =
          RemoteFrameBufferWidget(hostName: 'localhost');
      expect(widget.localCursor, isTrue);
      expect(widget.pressFeedback, isTrue);
      expect(widget.fallbackCursor, SystemMouseCursors.basic);
    });

    test('the options can be changed', () {
      final RemoteFrameBufferWidget widget = RemoteFrameBufferWidget(
        fallbackCursor: SystemMouseCursors.precise,
        hostName: 'localhost',
        localCursor: false,
        pressFeedback: false,
      );
      expect(widget.fallbackCursor, SystemMouseCursors.precise);
      expect(widget.localCursor, isFalse);
      expect(widget.pressFeedback, isFalse);
    });
  });
}
