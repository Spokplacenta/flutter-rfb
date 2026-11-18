# flutter_rfb

A VNC / Remote Framebuffer / RFC 6143 client purely written in Dart/Flutter.

[![](https://img.shields.io/pub/v/flutter_rfb)](https://pub.dev/packages/flutter_rfb)
[![](https://github.com/Goddchen/flutter-rfb/actions/workflows/main.yml/badge.svg)](https://github.com/Goddchen/flutter-rfb/)

## Motivation

We were searching a VNC viewer package for Flutter - without success.
Then there was a discussion about how complex the protocol is and wether we should implement it ourself.
Estimations ranged from 5 days to 100 days and we began joking that I'd be able to do it "after the weekend".
And here we are, after a weekend, with the first, minimal, VNC viewer implementation.

## Supported Features

For a list of currently supported protocol features please head over to the [dart_rfb](https://pub.dev/packages/dart_rfb) package.

## Installation

As simple as `dart pub add flutter_rfb`.

Or manually add `flutter_rfb: ^<latest-version>` to your `pubspec.yaml`.

## Usage

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(final BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Flutter RFB Example'),
          ),
          body: Center(
            child: InteractiveViewer(
              constrained: true,
              maxScale: 10,
              child: RemoteFrameBufferWidget(
                hostName: '127.0.0.1',
                onError: (final Object error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $error'),
                    ),
                  );
                },
                password: 'password',
              ),
            ),
          ),
        ),
      );
}
```

### Options

- `pixelFormat`: the pixel format asked to the server, `RemoteFrameBufferPixelFormat.rgb565` (16 bits) by default.
- `encodings`: the real encodings announced, in order of preference, among `RemoteFrameBufferWidget.supportedEncodings` (ZRLE, ZLib, Hextile, CopyRect, Raw, also the default). Raw is added at the end when missing; an invalid list throws an `ArgumentError`. Read once per connection: change the widget's key to reconnect with another list.
- `localCursor` (default `true`): the cursor is drawn locally at the mouse, without waiting for the server, when the server supports the Cursor pseudo-encoding. Nothing is drawn for touch input.
- `fallbackCursor` (default `SystemMouseCursors.basic`): with `localCursor`, the system cursor shown until the server's cursor shape arrives, or while that shape is invisible (0x0, as some HMIs send). The system cursor is hidden only while a visible remote shape is drawn.
- `pipelineUpdateRequests` (default `true`): the next update request leaves as soon as an update starts arriving. With `false`, it leaves once the update is read, one round trip per update.
- `fullRefreshInterval` (`Duration?`, default `null`, off): asks for the whole screen again (non-incremental update request) at this period, for servers that leave stale areas (e.g. Qt 4 QWS).
- `refreshAfterChange` (`Duration?`, default `null`, off): asks for the whole screen once, this long after an update covering at least 20 % of the screen (a screen change). Another screen change before then pushes it back; the update answering the refresh does not schedule another one.
- `pressFeedback` (default `true`) and `pressFeedbackColor`: a halo shown at once at each press, fading out in 250 ms.
- `syncLocalClipboardToRemote` (default `true`): push the local clipboard to the server.

## Learn More

https://pub.dev/packages/dart_rfb

https://www.rfc-editor.org/rfc/rfc6143
