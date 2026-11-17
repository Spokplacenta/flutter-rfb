import 'dart:typed_data';
import 'dart:ui';

import 'package:dart_rfb/dart_rfb.dart';
import 'package:flutter_rfb/src/bgra_opaque.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_widget.dart';
import 'package:flutter_test/flutter_test.dart';

/// A framebuffer of [width] x [height] pixels where every pixel holds its own
/// index in all 4 bytes, so moved pixels are easy to follow.
ByteData _numberedFrameBuffer(final int width, final int height) {
  final Uint8List bytes = Uint8List(width * height * 4);
  for (int i = 0; i < width * height; i++) {
    bytes.fillRange(i * 4, i * 4 + 4, i);
  }
  return ByteData.sublistView(bytes);
}

/// The pixel indexes of [frameBuffer], one per pixel.
List<int> _pixels(final ByteData frameBuffer) => <int>[
      for (int i = 0; i < frameBuffer.lengthInBytes; i += 4)
        frameBuffer.getUint8(i),
    ];

RemoteFrameBufferClientUpdateRectangle _copyRect({
  required final int sourceX,
  required final int sourceY,
  required final int x,
  required final int y,
  required final int width,
  required final int height,
}) =>
    RemoteFrameBufferClientUpdateRectangle(
      byteData: ByteData(4)
        ..setUint16(0, sourceX)
        ..setUint16(2, sourceY),
      encodingType: const RemoteFrameBufferEncodingType.copyRect(),
      height: height,
      width: width,
      x: x,
      y: y,
    );

void main() {
  group('updateFrameBuffer', () {
    test('copies a Raw rectangle row by row at its position', () async {
      final ByteData frameBuffer = ByteData(4 * 3 * 4);
      final Uint8List rectangle = Uint8List.fromList(
        List<int>.generate(2 * 2 * 4, (final int i) => i ~/ 4 + 1),
      );
      await RemoteFrameBufferWidgetState.updateFrameBuffer(
        frameBuffer: frameBuffer,
        frameBufferSize: const Size(4, 3),
        rectangle: RemoteFrameBufferClientUpdateRectangle(
          byteData: ByteData.sublistView(rectangle),
          encodingType: const RemoteFrameBufferEncodingType.raw(),
          height: 2,
          width: 2,
          x: 1,
          y: 1,
        ),
      ).run();
      expect(_pixels(frameBuffer), <int>[
        0, 0, 0, 0, //
        0, 1, 2, 0, //
        0, 3, 4, 0, //
      ]);
    });
  });

  group('copyRect', () {
    test('copies a non-overlapping area', () {
      final ByteData frameBuffer = _numberedFrameBuffer(4, 2);
      RemoteFrameBufferWidgetState.copyRect(
        frameBuffer: frameBuffer,
        frameBufferWidth: 4,
        rectangle: _copyRect(
          sourceX: 0,
          sourceY: 0,
          x: 2,
          y: 1,
          width: 2,
          height: 1,
        ),
      );
      expect(_pixels(frameBuffer), <int>[0, 1, 2, 3, 4, 5, 0, 1]);
    });

    test('handles a downward overlap (scrolling content down)', () {
      final ByteData frameBuffer = _numberedFrameBuffer(2, 4);
      RemoteFrameBufferWidgetState.copyRect(
        frameBuffer: frameBuffer,
        frameBufferWidth: 2,
        rectangle: _copyRect(
          sourceX: 0,
          sourceY: 0,
          x: 0,
          y: 1,
          width: 2,
          height: 3,
        ),
      );
      expect(_pixels(frameBuffer), <int>[0, 1, 0, 1, 2, 3, 4, 5]);
    });

    test('handles an upward overlap (scrolling content up)', () {
      final ByteData frameBuffer = _numberedFrameBuffer(2, 4);
      RemoteFrameBufferWidgetState.copyRect(
        frameBuffer: frameBuffer,
        frameBufferWidth: 2,
        rectangle: _copyRect(
          sourceX: 0,
          sourceY: 1,
          x: 0,
          y: 0,
          width: 2,
          height: 3,
        ),
      );
      expect(_pixels(frameBuffer), <int>[2, 3, 4, 5, 6, 7, 6, 7]);
    });

    test('handles a horizontal overlap on the same rows', () {
      final ByteData frameBuffer = _numberedFrameBuffer(4, 1);
      RemoteFrameBufferWidgetState.copyRect(
        frameBuffer: frameBuffer,
        frameBufferWidth: 4,
        rectangle: _copyRect(
          sourceX: 0,
          sourceY: 0,
          x: 1,
          y: 0,
          width: 3,
          height: 1,
        ),
      );
      expect(_pixels(frameBuffer), <int>[0, 0, 1, 2]);
    });
  });

  test('forceBgraOpaque sets the high byte without touching colors', () {
    final Uint8List pixels = Uint8List.fromList(<int>[
      10, 20, 30, 0, //
      255, 0, 128, 0, //
    ]);
    forceBgraOpaque(pixels);
    expect(pixels, <int>[10, 20, 30, 255, 255, 0, 128, 255]);
  });
}
