import 'package:flutter_rfb/flutter_rfb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the default pixel format is 16 bits (rgb565)', () {
    expect(
      RemoteFrameBufferWidget(hostName: 'localhost').pixelFormat,
      RemoteFrameBufferPixelFormat.rgb565,
    );
  });

  test('the pixel format can be chosen', () {
    expect(
      RemoteFrameBufferWidget(
        hostName: 'localhost',
        pixelFormat: RemoteFrameBufferPixelFormat.bgr233,
      ).pixelFormat,
      RemoteFrameBufferPixelFormat.bgr233,
    );
  });
}
