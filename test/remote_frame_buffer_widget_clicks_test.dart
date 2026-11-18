import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter_rfb/flutter_rfb.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_local_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

/// The remote screen: 4x2 pixels.
const int _width = 4;
const int _height = 2;

/// A RFC 6143 server on loopback, driven by the test: the RFB client runs in
/// the widget's own isolate and talks to it through a real socket.
class _Server {
  final ServerSocket _serverSocket;
  final BytesBuilder _received = BytesBuilder();
  Socket? _socket;

  _Server._(this._serverSocket) {
    _serverSocket.listen((final Socket socket) {
      _socket = socket
        ..setOption(SocketOption.tcpNoDelay, true)
        ..listen(_received.add)
        ..add('RFB 003.008\n'.codeUnits);
    });
  }

  static Future<_Server> start() async =>
      _Server._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  int get port => _serverSocket.port;

  /// How many handshake replies were sent.
  int _handshakeStep = 0;

  /// Moves the handshake forward as far as the client's bytes allow.
  void handshake() {
    final int length = _received.length;
    if (_handshakeStep == 0 && length >= 12) {
      _socket!.add(<int>[1, 1]); // one security type: none
      _handshakeStep++;
    }
    if (_handshakeStep == 1 && length >= 13) {
      _socket!.add(<int>[0, 0, 0, 0]); // security result: OK
      _handshakeStep++;
    }
    if (_handshakeStep == 2 && length >= 14) {
      // A native 16 bpp (RGB565) server of 4x2 pixels named "A".
      final ByteData serverInit = ByteData(24)
        ..setUint16(0, _width)
        ..setUint16(2, _height)
        ..setUint8(4, 16)
        ..setUint8(5, 16)
        ..setUint8(7, 1)
        ..setUint16(8, 31)
        ..setUint16(10, 63)
        ..setUint16(12, 31)
        ..setUint8(14, 11)
        ..setUint8(15, 5)
        ..setUint32(20, 1);
      _socket!.add(<int>[...serverInit.buffer.asUint8List(), 0x41]);
      _handshakeStep++;
    }
  }

  bool get handshakeDone => _handshakeStep == 3;

  void send(final List<int> bytes) => _socket!.add(bytes);

  /// The PointerEvent messages the client sent, as (buttons, x, y).
  List<(int, int, int)> pointerEvents() {
    final ByteData bytes = ByteData.sublistView(_received.toBytes());
    // ClientInit and the handshake replies: 12 + 1 + 1 bytes.
    int offset = 14;
    final List<(int, int, int)> events = <(int, int, int)>[];
    while (offset < bytes.lengthInBytes) {
      final int type = bytes.getUint8(offset);
      final int length = switch (type) {
        0 => 20, // SetPixelFormat
        2 => 4 + 4 * bytes.getUint16(offset + 2), // SetEncodings
        3 => 10, // FramebufferUpdateRequest
        4 => 8, // KeyEvent
        5 => 6, // PointerEvent
        6 => 8 + bytes.getUint32(offset + 4), // ClientCutText
        _ => throw StateError('Unknown client message $type at $offset'),
      };
      if (offset + length > bytes.lengthInBytes) {
        break;
      }
      if (type == 5) {
        events.add(
          (
            bytes.getUint8(offset + 1),
            bytes.getUint16(offset + 2),
            bytes.getUint16(offset + 4),
          ),
        );
      }
      offset += length;
    }
    return events;
  }

  Future<void> close() async {
    await _socket?.close();
    await _serverSocket.close();
  }
}

/// A FramebufferUpdate with one Raw rectangle covering the screen, at
/// 16 bpp.
List<int> _rawUpdate() => <int>[
      0, 0, 0, 1, // type, padding, 1 rectangle
      0, 0, 0, 0, 0, _width, 0, _height, // x, y, width, height
      0, 0, 0, 0, // Raw
      for (int i = 0; i < _width * _height; i++) ...<int>[0x1F, 0x00],
    ];

/// A FramebufferUpdate with a 2x3 cursor only, hotspot (1, 2).
List<int> _cursorUpdate() => <int>[
      0, 0, 0, 1,
      0, 1, 0, 2, 0, 2, 0, 3, // hotspot x, y, width, height
      0xFF, 0xFF, 0xFF, 0x11, // Cursor (-239)
      for (int i = 0; i < 2 * 3; i++) ...<int>[0x00, 0xF8],
      0xC0, 0xC0, 0xC0, // mask: every pixel shown
    ];

/// A FramebufferUpdate with an invisible (0x0) cursor only, as sent by some
/// HMIs.
const List<int> _invisibleCursorUpdate = <int>[
  0, 0, 0, 1,
  0, 0, 0, 0, 0, 0, 0, 0, // hotspot, 0x0
  0xFF, 0xFF, 0xFF, 0x11, // Cursor (-239), no data
];

void main() {
  testWidgets(
      'clicks reach the server inside InteractiveViewer and RotatedBox, '
      'while an update is arriving and when a cursor shape comes; '
      'the fallback cursor follows invisible shapes',
      (final WidgetTester tester) async {
    final _Server server = (await tester.runAsync(_Server.start))!;
    addTearDown(() => tester.runAsync(server.close));

    /// Lets the real event loop run (sockets, isolate ports, image decoding),
    /// then pumps a frame.
    Future<void> settle([final int milliseconds = 50]) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: milliseconds)),
      );
      server.handshake();
      await tester.pump();
    }

    Future<void> until(final bool Function() condition) async {
      for (int i = 0; i < 100 && !condition(); i++) {
        await settle(20);
      }
      expect(condition(), isTrue);
    }

    // As in LavMan's VNC screen.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: InteractiveViewer(
            maxScale: 8,
            child: RotatedBox(
              quarterTurns: 1,
              child: RemoteFrameBufferWidget(
                connectingWidget: const SizedBox(),
                hostName: '127.0.0.1',
                port: server.port,
                syncLocalClipboardToRemote: false,
              ),
            ),
          ),
        ),
      ),
    );
    await until(() => server.handshakeDone);
    // The first update request, then the first frame.
    await settle();
    server.send(_rawUpdate());
    await until(() => find.byType(RawImage).evaluate().isNotEmpty);
    await settle();

    final Finder image = find.byType(RawImage);
    final Offset center = tester.getCenter(image);
    int expected = 0;

    Future<void> expectClick(final String what) async {
      expected += 2;
      await until(() => server.pointerEvents().length >= expected);
      final List<(int, int, int)> events = server.pointerEvents();
      expect(events, hasLength(expected), reason: what);
      final (int, int, int) down = events[expected - 2];
      final (int, int, int) up = events[expected - 1];
      expect(down.$1, 1, reason: '$what: button 1 pressed');
      expect(up.$1, 0, reason: '$what: buttons released');
      expect(down.$2, inInclusiveRange(0, _width - 1), reason: what);
      expect(down.$3, inInclusiveRange(0, _height - 1), reason: what);
    }

    Future<void> click(
      final PointerDeviceKind kind, {
      final List<int>? sentWhilePressed,
    }) async {
      final TestGesture gesture = await tester.startGesture(center, kind: kind);
      await settle();
      if (sentWhilePressed != null) {
        server.send(sentWhilePressed);
        await settle();
      }
      await gesture.up();
      await settle();
      if (kind == PointerDeviceKind.mouse) {
        await gesture.removePointer();
      }
    }

    // An update is still arriving, as on a slow link: the server holds its
    // last byte.
    final List<int> update = _rawUpdate();
    server.send(update.sublist(0, update.length - 1));
    await settle();
    await click(PointerDeviceKind.mouse);
    await expectClick('mouse, update arriving');
    await click(PointerDeviceKind.touch);
    await expectClick('touch, update arriving');
    server
      ..send(<int>[update.last])
      // A cursor shape between two presses.
      ..send(_cursorUpdate());
    await until(
      () => tester
          .state<RemoteFrameBufferLocalFeedbackState>(
            find.byType(RemoteFrameBufferLocalFeedback),
          )
          .widget
          .cursor
          .isSome(),
    );
    await click(PointerDeviceKind.mouse);
    await expectClick('mouse, after a cursor');
    await click(PointerDeviceKind.touch);
    await expectClick('touch, after a cursor');

    // A cursor shape, then a partial update, during the press.
    await click(
      PointerDeviceKind.mouse,
      sentWhilePressed: <int>[
        ..._cursorUpdate(),
        ...update.sublist(0, update.length - 1),
      ],
    );
    await expectClick('mouse, cursor during the press');
    server.send(<int>[update.last]);
    await click(
      PointerDeviceKind.touch,
      sentWhilePressed: _cursorUpdate(),
    );
    await expectClick('touch, cursor during the press');

    // Hovering: the visible shape hides the system cursor, an invisible one
    // brings the fallback arrow back, without the mouse leaving.
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: center);
    await settle();
    MouseCursor? activeCursor() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
    expect(activeCursor(), SystemMouseCursors.none);
    server.send(_invisibleCursorUpdate);
    await until(() => activeCursor() == SystemMouseCursors.basic);
    server.send(_cursorUpdate());
    await until(() => activeCursor() == SystemMouseCursors.none);
    await mouse.removePointer();

    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
