import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' hide Image;
import 'package:flutter_rfb/src/remote_frame_buffer_isolate_messages.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_pointer_listener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;

/// A remote screen of 4x2 pixels shown in a 40x20 widget: one remote pixel
/// is 10x10 logical pixels.
const Size _widgetSize = Size(40, 20);

class _Harness {
  final List<RemoteFrameBufferIsolateSendMessagePointerEvent> _received =
      <RemoteFrameBufferIsolateSendMessagePointerEvent>[];
  final ReceivePort _receivePort = ReceivePort();
  late final Image _image;

  Future<void> setUp(final WidgetTester tester) async {
    _receivePort.listen((final Object? message) {
      if (message is RemoteFrameBufferIsolateSendMessagePointerEvent) {
        _received.add(message);
      }
    });
    _image = (await tester.runAsync(
      () => createTestImage(width: 4, height: 2),
    ))!;
  }

  void dispose() {
    _receivePort.close();
    _image.dispose();
  }

  Widget build({final bool inInteractiveViewer = false}) {
    final Widget listener = Center(
      child: SizedBox.fromSize(
        size: _widgetSize,
        child: RemoteFrameBufferPointerListener(
          image: _image,
          remoteFrameBufferWidgetSize: _widgetSize,
          sendPort: some(_receivePort.sendPort),
          child: const SizedBox.expand(),
        ),
      ),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: inInteractiveViewer
          ? InteractiveViewer(maxScale: 8, child: listener)
          : listener,
    );
  }

  /// The pointer events sent so far, then forgets them.
  Future<List<RemoteFrameBufferIsolateSendMessagePointerEvent>> take(
    final WidgetTester tester,
  ) async {
    // Port messages are delivered by the real event loop.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> received =
        List<RemoteFrameBufferIsolateSendMessagePointerEvent>.of(_received);
    _received.clear();
    return received;
  }
}

/// The top left corner of remote pixel ([x], [y]), in global coordinates.
Offset _at(final WidgetTester tester, final int x, final int y) =>
    tester.getTopLeft(find.byType(RemoteFrameBufferPointerListener)) +
    Offset(x * 10.0 + 5, y * 10.0 + 5);

void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  testWidgets('a press is sent at once, a release clears the buttons',
      (final WidgetTester tester) async {
    await harness.setUp(tester);
    await tester.pumpWidget(harness.build());
    final TestGesture gesture = await tester.startGesture(_at(tester, 1, 0));
    // No frame pumped: the press does not wait for a gesture to be decided.
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> down =
        await harness.take(tester);
    expect(down, hasLength(1));
    expect(down.single.button1Down, isTrue);
    expect((down.single.x, down.single.y), (1, 0));
    await gesture.up();
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> up =
        await harness.take(tester);
    expect(up, hasLength(1));
    expect(up.single.button1Down, isFalse);
    expect((up.single.x, up.single.y), (1, 0));
  });

  testWidgets('moves with a button pressed are sent once per frame',
      (final WidgetTester tester) async {
    await harness.setUp(tester);
    await tester.pumpWidget(harness.build());
    final TestGesture gesture = await tester.startGesture(_at(tester, 0, 0));
    await harness.take(tester);
    await gesture.moveTo(_at(tester, 1, 0));
    await gesture.moveTo(_at(tester, 2, 0));
    await gesture.moveTo(_at(tester, 3, 1));
    expect(await harness.take(tester), isEmpty);
    await tester.pump();
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> moves =
        await harness.take(tester);
    expect(moves, hasLength(1));
    expect(moves.single.button1Down, isTrue);
    expect((moves.single.x, moves.single.y), (3, 1));
    await gesture.up();
  });

  testWidgets('the secondary mouse button is RFB button 3',
      (final WidgetTester tester) async {
    await harness.setUp(tester);
    await tester.pumpWidget(harness.build());
    final TestGesture gesture = await tester.startGesture(
      _at(tester, 2, 1),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> down =
        await harness.take(tester);
    expect(down.single.button1Down, isFalse);
    expect(down.single.button3Down, isTrue);
    await gesture.up();
    expect((await harness.take(tester)).single.button3Down, isFalse);
  });

  testWidgets('only the first finger is forwarded',
      (final WidgetTester tester) async {
    await harness.setUp(tester);
    await tester.pumpWidget(harness.build());
    final TestGesture first = await tester.startGesture(_at(tester, 0, 0));
    final TestGesture second =
        await tester.startGesture(_at(tester, 3, 1), pointer: 7);
    await second.up();
    await first.up();
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> events =
        await harness.take(tester);
    expect(
      events.map(
        (final RemoteFrameBufferIsolateSendMessagePointerEvent e) =>
            (e.button1Down, e.x, e.y),
      ),
      <(bool, int, int)>[(true, 0, 0), (false, 0, 0)],
    );
  });

  testWidgets('inside an InteractiveViewer, the press is still immediate',
      (final WidgetTester tester) async {
    await harness.setUp(tester);
    await tester.pumpWidget(harness.build(inInteractiveViewer: true));
    final TestGesture gesture = await tester.startGesture(_at(tester, 1, 1));
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> down =
        await harness.take(tester);
    expect(down.single.button1Down, isTrue);
    expect((down.single.x, down.single.y), (1, 1));
    await gesture.up();
  });

  testWidgets('a cancelled pointer releases the buttons',
      (final WidgetTester tester) async {
    await harness.setUp(tester);
    await tester.pumpWidget(harness.build());
    final TestGesture gesture = await tester.startGesture(_at(tester, 2, 0));
    await harness.take(tester);
    await gesture.cancel();
    final List<RemoteFrameBufferIsolateSendMessagePointerEvent> events =
        await harness.take(tester);
    expect(events.single.button1Down, isFalse);
  });
}
