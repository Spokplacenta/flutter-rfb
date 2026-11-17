import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:dart_rfb/dart_rfb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rfb/src/bgra_opaque.dart';
import 'package:flutter_rfb/src/child_size_notifier_widget.dart';
import 'package:flutter_rfb/src/extensions/logical_keyboard_key_extensions.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_client_isolate.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_isolate_messages.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_pointer_listener.dart';
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
  final RemoteFrameBufferPixelFormat _pixelFormat;
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
  ///
  /// [pixelFormat] is the format asked to the server:
  /// [RemoteFrameBufferPixelFormat.rgb565] (16 bits, the default),
  /// [RemoteFrameBufferPixelFormat.bgr233] (8 bits, 64 colours, the least
  /// data) or [RemoteFrameBufferPixelFormat.bgra8888] (32 bits, full colour).
  RemoteFrameBufferWidget({
    super.key,
    final Widget? connectingWidget,
    required final String hostName,
    final void Function(Object error)? onError,
    final VoidCallback? onFirstFrame,
    final String? password,
    final RemoteFrameBufferPixelFormat pixelFormat =
        RemoteFrameBufferPixelFormat.rgb565,
    final int port = 5900,
    final bool syncLocalClipboardToRemote = true,
  })  : _connectingWidget = optionOf(connectingWidget),
        _hostName = hostName,
        _onError = optionOf(onError),
        _onFirstFrame = optionOf(onFirstFrame),
        _password = optionOf(password),
        _pixelFormat = pixelFormat,
        _port = port,
        _syncLocalClipboardToRemote = syncLocalClipboardToRemote;

  /// The pixel format asked to the server.
  @visibleForTesting
  RemoteFrameBufferPixelFormat get pixelFormat => _pixelFormat;

  @override
  State<RemoteFrameBufferWidget> createState() =>
      RemoteFrameBufferWidgetState();
}

@visibleForTesting
class RemoteFrameBufferWidgetState extends State<RemoteFrameBufferWidget> {
  Timer? _clipBoardMonitorTimer;
  Option<ByteData> _frameBuffer = none();
  Option<Image> _image = none();

  /// A [decodeImageFromPixels] is running: at most one at a time.
  bool _imageDecodeBusy = false;

  /// The framebuffer changed since the last image was started.
  bool _imageDirty = false;

  /// A publication is scheduled for the next frame (vsync).
  bool _publishScheduled = false;
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
          builder: (
            final BuildContext context,
            final Size size,
            final Widget? child,
          ) =>
              RemoteFrameBufferPointerListener(
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

  /// Decodes the current [frameBuffer] into a new [Image].
  ///
  /// [onDone] is always called, even when nothing is decoded, so that the
  /// next publication is never blocked.
  void _decodeAndUpdateImage({
    required final ByteData frameBuffer,
    required final int frameBufferHeight,
    required final int frameBufferWidth,
    required final VoidCallback onDone,
  }) {
    final int w = frameBufferWidth;
    final int h = frameBufferHeight;
    if (w <= 0 || h <= 0) {
      _logger.warning('Framebuffer update: invalid dimensions (${w}x$h).');
      onDone();
      return;
    }
    final int expectedBytes = w * h * 4;
    if (frameBuffer.lengthInBytes < expectedBytes) {
      _logger.warning(
        'Framebuffer update: buffer too short (${frameBuffer.lengthInBytes} < $expectedBytes).',
      );
      onDone();
      return;
    }
    // A copy: the framebuffer keeps changing while the image is decoded.
    final Uint8List pixels = Uint8List.fromList(
      frameBuffer.buffer.asUint8List(
        frameBuffer.offsetInBytes,
        expectedBytes,
      ),
    );
    forceBgraOpaque(pixels);
    decodeImageFromPixels(
      pixels,
      w,
      h,
      PixelFormat.bgra8888,
      (final Image result) {
        if (!mounted) {
          result.dispose();
          onDone();
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
        onDone();
      },
    );
  }

  /// Publishes the framebuffer at the next vsync.
  ///
  /// Updates received in between are coalesced: at most one [Image] is being
  /// decoded at a time, and the most recent framebuffer always wins. No fixed
  /// frame rate cap.
  void _publishFrame({
    required final ByteData frameBuffer,
    required final int frameBufferHeight,
    required final int frameBufferWidth,
  }) {
    _imageDirty = true;
    if (_imageDecodeBusy || _publishScheduled) {
      return;
    }
    _publishScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((final _) {
      _publishScheduled = false;
      if (!mounted || !_imageDirty) {
        return;
      }
      _imageDirty = false;
      _imageDecodeBusy = true;
      _decodeAndUpdateImage(
        frameBuffer: frameBuffer,
        frameBufferHeight: frameBufferHeight,
        frameBufferWidth: frameBufferWidth,
        onDone: () {
          _imageDecodeBusy = false;
          if (mounted && _imageDirty) {
            _publishFrame(
              frameBuffer: frameBuffer,
              frameBufferHeight: frameBufferHeight,
              frameBufferWidth: frameBufferWidth,
            );
          }
        },
      );
    });
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
                  copyRect: () async => copyRect(
                    frameBuffer: frameBuffer,
                    frameBufferWidth: update.frameBufferWidth,
                    rectangle: rectangle,
                  ),
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
              // The next update request is sent by the RFB client itself as
              // soon as it reads the header of this update (pipelining).
              _publishFrame(
                frameBuffer: frameBuffer,
                frameBufferHeight: update.frameBufferHeight,
                frameBufferWidth: update.frameBufferWidth,
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
                unawaited(
                  _handleFrameBufferUpdateMessage(update: update).run(),
                );
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
          pixelFormat: widget._pixelFormat,
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
          final int width = rectangle.width;
          final int height = rectangle.height;
          if (width <= 0 || height <= 0) {
            return;
          }
          final int dstStride = frameBufferSize.width.toInt() * 4;
          final int srcStride = width * 4;
          final Uint8List src = rectangle.byteData.buffer.asUint8List(
            rectangle.byteData.offsetInBytes,
            rectangle.byteData.lengthInBytes,
          );
          final Uint8List dst = frameBuffer.buffer.asUint8List(
            frameBuffer.offsetInBytes,
            frameBuffer.lengthInBytes,
          );
          for (int y = 0; y < height; y++) {
            final int dstIndex =
                ((rectangle.y + y) * dstStride) + rectangle.x * 4;
            dst.setRange(dstIndex, dstIndex + srcStride, src, y * srcStride);
          }
        },
        (final Object error, final _) => error,
      );

  /// Copies the source area of a CopyRect [rectangle] to its destination in
  /// [frameBuffer], row by row. Source and destination may overlap.
  @visibleForTesting
  static void copyRect({
    required final ByteData frameBuffer,
    required final int frameBufferWidth,
    required final RemoteFrameBufferClientUpdateRectangle rectangle,
  }) {
    final int width = rectangle.width;
    final int height = rectangle.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    final int sourceX = rectangle.byteData.getUint16(0);
    final int sourceY = rectangle.byteData.getUint16(2);
    final int stride = frameBufferWidth * 4;
    final int rowBytes = width * 4;
    final Uint8List pixels = frameBuffer.buffer.asUint8List(
      frameBuffer.offsetInBytes,
      frameBuffer.lengthInBytes,
    );
    // Through a row buffer, so a horizontal overlap is safe too.
    final Uint8List row = Uint8List(rowBytes);
    // Moving down: copy the bottom rows first, so none is overwritten before
    // it is read.
    final bool downward = sourceY < rectangle.y;
    for (int i = 0; i < height; i++) {
      final int y = downward ? height - 1 - i : i;
      final int srcIndex = ((sourceY + y) * stride) + sourceX * 4;
      row.setRange(0, rowBytes, pixels, srcIndex);
      final int dstIndex = ((rectangle.y + y) * stride) + rectangle.x * 4;
      pixels.setRange(dstIndex, dstIndex + rowBytes, row);
    }
  }
}
