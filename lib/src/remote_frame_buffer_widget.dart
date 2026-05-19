import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:dart_rfb/dart_rfb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rfb/src/child_size_notifier_widget.dart';
import 'package:flutter_rfb/src/extensions/logical_keyboard_key_extensions.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_client_isolate.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_gesture_detector.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_isolate_messages.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:logging/logging.dart';

final Logger _logger = Logger('RemoteFrameBufferWidget');

/// This widget displays the framebuffer associated with the RFB session.
/// On creation, it tries to establish a connection with the remote server
/// in an isolate. On success, it runs the read loop in that isolate.
class RemoteFrameBufferWidget extends StatefulWidget {
  final Option<Widget> _connectingWidget;
  final String _hostName;
  final Option<void Function(Object error)> _onError;
  final Option<VoidCallback> _onFirstFrame;
  final Option<String> _password;
  final int _port;
  final bool _syncLocalClipboardToRemote;

  /// Immediately tries to establish a connection to a remote server at
  /// [hostName]:[port], optionally using [password].
  ///
  /// Set [syncLocalClipboardToRemote] to `false` to avoid pushing the local
  /// clipboard to the remote server (useful when the host app copies logs or
  /// console text that must not be sent to the VNC session).
  ///
  /// [onFirstFrame] is called once after the first decoded framebuffer image
  /// is displayed.
  RemoteFrameBufferWidget({
    super.key,
    final Widget? connectingWidget,
    required final String hostName,
    final void Function(Object error)? onError,
    final VoidCallback? onFirstFrame,
    final String? password,
    final int port = 5900,
    final bool syncLocalClipboardToRemote = true,
  })  : _connectingWidget = optionOf(connectingWidget),
        _hostName = hostName,
        _onError = optionOf(onError),
        _onFirstFrame = optionOf(onFirstFrame),
        _password = optionOf(password),
        _port = port,
        _syncLocalClipboardToRemote = syncLocalClipboardToRemote;

  @override
  State<RemoteFrameBufferWidget> createState() =>
      RemoteFrameBufferWidgetState();
}

@visibleForTesting
class RemoteFrameBufferWidgetState extends State<RemoteFrameBufferWidget> {
  Timer? _clipBoardMonitorTimer;
  Option<ByteData> _frameBuffer = none();
  Option<Image> _image = none();
  Option<Isolate> _isolate = none();
  Option<SendPort> _isolateSendPort = none();
  final ValueNotifier<Size> _sizeValueNotifier = ValueNotifier<Size>(Size.zero);
  Option<StreamSubscription<Object?>> _streamSubscription = none();

  @override
  Widget build(final BuildContext context) => _image.match(
        _buildConnecting,
        (final Image image) => _buildImage(image: image),
      );

  @override
  void dispose() {
    _clipBoardMonitorTimer?.cancel();
    _streamSubscription.match(
      () {},
      (final StreamSubscription<Object?> subscription) =>
          unawaited(subscription.cancel()),
    );
    _image.match(
      () {},
      (final Image image) => image.dispose(),
    );
    _isolate.match(
      () {},
      (final Isolate isolate) => isolate.kill(),
    );
    HardwareKeyboard.instance.removeHandler(_keyEventHandler);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget._syncLocalClipboardToRemote) {
      _monitorClipBoard();
    }
    HardwareKeyboard.instance.addHandler(_keyEventHandler);
    unawaited(_initAsync());
  }

  Widget _buildConnecting() => widget._connectingWidget.getOrElse(
        () => const Center(
          child: CircularProgressIndicator(),
        ),
      );

  SizeTrackingWidget _buildImage({required final Image image}) =>
      SizeTrackingWidget(
        sizeValueNotifier: _sizeValueNotifier,
        child: ValueListenableBuilder<Size>(
          valueListenable: _sizeValueNotifier,
          builder: (final BuildContext context, final Size size, final Widget? child) =>
              RemoteFrameBufferGestureDetector(
            image: image,
            remoteFrameBufferWidgetSize: size,
            sendPort: _isolateSendPort,
            child: RawImage(
              image: image,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );

  void _decodeAndUpdateImage({
    required final ByteData frameBuffer,
    required final RemoteFrameBufferIsolateReceiveMessageFrameBufferUpdate
        message,
  }) {
    final int w = message.frameBufferWidth;
    final int h = message.frameBufferHeight;
    if (w <= 0 || h <= 0) {
      _logger.warning('Framebuffer update: invalid dimensions (${w}x$h).');
      return;
    }
    final int expectedBytes = w * h * 4;
    if (frameBuffer.lengthInBytes < expectedBytes) {
      _logger.warning(
        'Framebuffer update: buffer too short (${frameBuffer.lengthInBytes} < $expectedBytes).',
      );
      return;
    }
    final Uint8List pixels = frameBuffer.buffer.asUint8List(
      frameBuffer.offsetInBytes,
      expectedBytes,
    );
    decodeImageFromPixels(
      pixels,
      w,
      h,
      PixelFormat.bgra8888,
      (final Image result) {
        if (!mounted) {
          result.dispose();
          return;
        }
        final bool isFirstFrame = _image.isNone();
        setState(() {
          _image.match(
            () {},
            (final Image image) => image.dispose(),
          );
          _image = some(result);
        });
        if (isFirstFrame) {
          widget._onFirstFrame.match(
            () {},
            (final VoidCallback callback) {
              SchedulerBinding.instance.addPostFrameCallback((final _) {
                if (mounted) {
                  callback();
                }
              });
            },
          );
        }
        _isolateSendPort.match(
          () {},
          (final SendPort sendPort) => sendPort.send(
            const RemoteFrameBufferIsolateSendMessage.frameBufferUpdateRequest(),
          ),
        );
      },
    );
  }

  Task<void> _handleFrameBufferUpdateMessage({
    required final RemoteFrameBufferIsolateReceiveMessageFrameBufferUpdate
        update,
  }) =>
      Task<void>(() async {
        _logger.finer(
          'Received new update message with ${update.update.rectangles.length} rectangles',
        );
        _isolateSendPort = some(update.sendPort);
        if (_frameBuffer.isNone()) {
          _frameBuffer = some(
            ByteData(
              update.frameBufferHeight * update.frameBufferWidth * 4,
            ),
          );
        }
        unawaited(
          _frameBuffer.match(
            () async {},
            (final ByteData frameBuffer) async {
              for (final RemoteFrameBufferClientUpdateRectangle rectangle
                  in update.update.rectangles) {
                await rectangle.encodingType.when(
                  copyRect: () async {
                    final int sourceX = rectangle.byteData.getUint16(0);
                    final int sourceY = rectangle.byteData.getUint16(2);
                    final BytesBuilder bytesBuilder = BytesBuilder();
                    for (int row = 0; row < rectangle.height; row++) {
                      for (int column = 0; column < rectangle.width; column++) {
                        bytesBuilder.add(
                          frameBuffer.buffer.asUint8List(
                            ((sourceY + row) * update.frameBufferWidth +
                                    sourceX +
                                    column) *
                                4,
                            4,
                          ),
                        );
                      }
                    }
                    return (await updateFrameBuffer(
                      frameBuffer: frameBuffer,
                      frameBufferSize: Size(
                        update.frameBufferWidth.toDouble(),
                        update.frameBufferHeight.toDouble(),
                      ),
                      rectangle: rectangle.copyWith(
                        encodingType: const RemoteFrameBufferEncodingType.raw(),
                        byteData: ByteData.sublistView(
                          bytesBuilder.toBytes(),
                        ),
                      ),
                    ).run())
                        .match(
                      (final Object error) => debugPrint(
                        'RemoteFrameBufferWidget: updateFrameBuffer $error',
                      ),
                      (final _) {},
                    );
                  },
                  raw: () async => (await updateFrameBuffer(
                    frameBuffer: frameBuffer,
                    frameBufferSize: Size(
                      update.frameBufferWidth.toDouble(),
                      update.frameBufferHeight.toDouble(),
                    ),
                    rectangle: rectangle,
                  ).run())
                      .match(
                    (final Object error) => debugPrint(
                      'RemoteFrameBufferWidget: updateFrameBuffer $error',
                    ),
                    (final _) {},
                  ),
                  zrle: () async => _logger.warning(
                    'ZRLE rectangle received — decoding should happen upstream in dart_rfb.',
                  ),
                  unsupported: (final ByteData bytes) async {},
                );
              }
              _decodeAndUpdateImage(
                frameBuffer: frameBuffer,
                message: update,
              );
            },
          ),
        );
      });

  /// Initializes logic that requires to be run asynchronous.
  Future<void> _initAsync() async {
    final ReceivePort receivePort = ReceivePort();
    _streamSubscription = some(
      receivePort.listen(
        (final Object? message) {
          if (message is List) {
            widget._onError.match(
              () {},
              (final void Function(Object error) onError) =>
                  onError(message.first),
            );
          } else if (message is RemoteFrameBufferIsolateReceiveMessage) {
            message.map(
              clipBoardUpdate: (
                final RemoteFrameBufferIsolateReceiveMessageClipBoardUpdate
                    update,
              ) =>
                  unawaited(
                    Clipboard.setData(ClipboardData(text: update.text)),
                  ),
              frameBufferUpdate: (
                final RemoteFrameBufferIsolateReceiveMessageFrameBufferUpdate
                    update,
              ) {
                unawaited(_handleFrameBufferUpdateMessage(update: update).run());
              },
            );
          }
        },
      ),
    );
    _logger.info('Spawning new isolate for RFB client');
    _isolate = some(
      await Isolate.spawn(
        startRemoteFrameBufferClient,
        RemoteFrameBufferIsolateInitMessage(
          hostName: widget._hostName,
          password: widget._password,
          port: widget._port,
          sendPort: receivePort.sendPort,
        ),
        onError: receivePort.sendPort,
      ),
    );
  }

  void _monitorClipBoard() {
    Option<String> lastClipBoardContent = none();
    _clipBoardMonitorTimer = Timer.periodic(
      const Duration(seconds: 1),
      (final _) async {
        optionOf(await Clipboard.getData(Clipboard.kTextPlain))
            .flatMap((final ClipboardData data) => optionOf(data.text))
            .filter(
              (final String text) => lastClipBoardContent.match(
                () => true,
                (final String lastClipBoardContent) =>
                    lastClipBoardContent != text,
              ),
            )
            .match(
              () {},
              (final String text) => _isolateSendPort.match(
                () {},
                (final SendPort sendPort) {
                  lastClipBoardContent = some(text);
                  sendPort.send(
                    RemoteFrameBufferIsolateSendMessage.clipBoardUpdate(
                      text: text,
                    ),
                  );
                },
              ),
            );
      },
    );
  }

  bool _keyEventHandler(final KeyEvent event) {
    _isolateSendPort.match(
      () {},
      (final SendPort sendPort) => sendPort.send(
        RemoteFrameBufferIsolateSendMessage.keyEvent(
          down: event is KeyDownEvent,
          key: event.logicalKey.asXWindowSystemKey(),
        ),
      ),
    );
    return false;
  }

  /// Updates [frameBuffer] with the given [rectangle]s.
  @visibleForTesting
  static TaskEither<Object, void> updateFrameBuffer({
    required final ByteData frameBuffer,
    required final Size frameBufferSize,
    required final RemoteFrameBufferClientUpdateRectangle rectangle,
  }) =>
      TaskEither<Object, void>.tryCatch(
        () async {
          for (int y = 0; y < rectangle.height; y++) {
            for (int x = 0; x < rectangle.width; x++) {
              final int frameBufferX = rectangle.x + x;
              final int frameBufferY = rectangle.y + y;
              final int pixelBytes =
                  rectangle.byteData.getUint32((y * rectangle.width + x) * 4);
              frameBuffer.setUint32(
                ((frameBufferY * frameBufferSize.width + frameBufferX) * 4)
                    .toInt(),
                pixelBytes,
              );
            }
          }
        },
        (final Object error, final _) => error,
      );
}
