import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_rfb/flutter_rfb.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_isolate_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

void main() {
  test('the default encodings are ZRLE, ZLib, Hextile, CopyRect, Raw', () {
    expect(
      RemoteFrameBufferWidget(hostName: 'localhost').encodings,
      const <RemoteFrameBufferEncodingType>[
        RemoteFrameBufferEncodingType.zrle(),
        RemoteFrameBufferEncodingType.zlib(),
        RemoteFrameBufferEncodingType.hextile(),
        RemoteFrameBufferEncodingType.copyRect(),
        RemoteFrameBufferEncodingType.raw(),
      ],
    );
    expect(
      RemoteFrameBufferWidget.defaultEncodings,
      RemoteFrameBufferWidget.supportedEncodings,
    );
  });

  test('a chosen list keeps its order and ends with Raw', () {
    expect(
      RemoteFrameBufferWidget(
        encodings: const <RemoteFrameBufferEncodingType>[
          RemoteFrameBufferEncodingType.hextile(),
          RemoteFrameBufferEncodingType.zlib(),
        ],
        hostName: 'localhost',
      ).encodings,
      const <RemoteFrameBufferEncodingType>[
        RemoteFrameBufferEncodingType.hextile(),
        RemoteFrameBufferEncodingType.zlib(),
        RemoteFrameBufferEncodingType.raw(),
      ],
    );
  });

  for (final (String name, List<RemoteFrameBufferEncodingType> encodings)
      in <(String, List<RemoteFrameBufferEncodingType>)>[
    ('an empty list', const <RemoteFrameBufferEncodingType>[]),
    (
      'a pseudo-encoding',
      const <RemoteFrameBufferEncodingType>[
        RemoteFrameBufferEncodingType.cursor(),
      ],
    ),
    (
      'an unsupported encoding',
      <RemoteFrameBufferEncodingType>[
        RemoteFrameBufferEncodingType.unsupported(
          bytes: ByteData(4)..setInt32(0, 7),
        ),
      ],
    ),
  ]) {
    test('$name is rejected before any connection', () {
      expect(
        () => RemoteFrameBufferWidget(encodings: encodings, hostName: 'host'),
        throwsArgumentError,
      );
    });
  }

  test('the init message carries the encodings', () {
    final ReceivePort port = ReceivePort();
    addTearDown(port.close);
    RemoteFrameBufferIsolateInitMessage message(
      final List<RemoteFrameBufferEncodingType> encodings,
    ) =>
        RemoteFrameBufferIsolateInitMessage(
          encodings: encodings,
          fullRefreshInterval: null,
          hostName: 'host',
          localCursor: true,
          password: none(),
          pipelineUpdateRequests: true,
          pixelFormat: RemoteFrameBufferPixelFormat.rgb565,
          port: 5900,
          refreshAfterChange: null,
          sendPort: port.sendPort,
        );
    const List<RemoteFrameBufferEncodingType> zlib =
        <RemoteFrameBufferEncodingType>[
      RemoteFrameBufferEncodingType.zlib(),
      RemoteFrameBufferEncodingType.raw(),
    ];
    final RemoteFrameBufferIsolateInitMessage first = message(zlib);
    expect(first.encodings, zlib);
    expect(
      first,
      message(<RemoteFrameBufferEncodingType>[...zlib]),
      reason: 'equal lists, equal messages',
    );
    expect(
      first.hashCode,
      message(<RemoteFrameBufferEncodingType>[...zlib]).hashCode,
    );
    expect(first, isNot(message(RemoteFrameBufferWidget.defaultEncodings)));
    expect(
      first
          .copyWith(encodings: RemoteFrameBufferWidget.defaultEncodings)
          .encodings,
      RemoteFrameBufferWidget.defaultEncodings,
    );
    expect(first.copyWith(port: 1).encodings, zlib);
    expect(first.toString(), contains('encodings:'));
  });
}
