import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/widgets.dart' hide Image;
import 'package:flutter_rfb/src/remote_frame_buffer_isolate_messages.dart';
import 'package:fpdart/fpdart.dart';

class RemoteFrameBufferGestureDetector extends GestureDetector {
  final Image _image;
  final Size _remoteFrameBufferWidgetSize;
  final Option<SendPort> _sendPort;

  RemoteFrameBufferGestureDetector({
    super.key,
    required final Image image,
    required final Size remoteFrameBufferWidgetSize,
    required final Option<SendPort> sendPort,
    super.child,
  })  : _image = image,
        _remoteFrameBufferWidgetSize = remoteFrameBufferWidgetSize,
        _sendPort = sendPort;

  /// Check if the widget and image sizes are valid for coordinate calculations.
  bool get _hasValidSize =>
      _remoteFrameBufferWidgetSize.width > 0 &&
      _remoteFrameBufferWidgetSize.height > 0 &&
      _image.width > 0 &&
      _image.height > 0;

  /// Convert local position to remote framebuffer coordinates.
  /// 
  /// With BoxFit.contain, the image is scaled to fit while preserving aspect ratio.
  /// We need to calculate the actual scaling and offsets (centering) to map
  /// widget coordinates to image coordinates correctly.
  int _toRemoteX(final double localX) {
    if (!_hasValidSize) {
      return 0;
    }
    // Additional defensive checks for Infinity/NaN
    if (!localX.isFinite ||
        !_remoteFrameBufferWidgetSize.width.isFinite ||
        !_image.width.isFinite ||
        _remoteFrameBufferWidgetSize.width == 0 ||
        _image.width == 0) {
      return 0;
    }
    // Calculate scaling factors for both dimensions
    final double scaleX = _remoteFrameBufferWidgetSize.width / _image.width;
    final double scaleY = _remoteFrameBufferWidgetSize.height / _image.height;
    // With BoxFit.contain, the actual scale is the minimum to preserve aspect ratio
    final double actualScale = scaleX < scaleY ? scaleX : scaleY;
    // Calculate the displayed image size
    final double displayedWidth = _image.width * actualScale;
    // Calculate offset (centering) - area where the image doesn't fill the widget horizontally
    final double offsetX = (_remoteFrameBufferWidgetSize.width - displayedWidth) / 2;
    // Adjust local coordinates by subtracting the offset
    final double adjustedX = localX - offsetX;
    // Convert to image coordinates using the actual scale
    final double result = adjustedX / actualScale;
    if (!result.isFinite) {
      return 0;
    }
    // Clamp to valid image bounds
    return result.clamp(0, _image.width - 1).toInt();
  }

  int _toRemoteY(final double localY) {
    if (!_hasValidSize) {
      return 0;
    }
    // Additional defensive checks for Infinity/NaN
    if (!localY.isFinite ||
        !_remoteFrameBufferWidgetSize.height.isFinite ||
        !_image.height.isFinite ||
        _remoteFrameBufferWidgetSize.height == 0 ||
        _image.height == 0) {
      return 0;
    }
    // Calculate scaling factors for both dimensions
    final double scaleX = _remoteFrameBufferWidgetSize.width / _image.width;
    final double scaleY = _remoteFrameBufferWidgetSize.height / _image.height;
    // With BoxFit.contain, the actual scale is the minimum to preserve aspect ratio
    final double actualScale = scaleX < scaleY ? scaleX : scaleY;
    // Calculate the displayed image size
    final double displayedHeight = _image.height * actualScale;
    // Calculate offset (centering) - area where the image doesn't fill the widget vertically
    final double offsetY = (_remoteFrameBufferWidgetSize.height - displayedHeight) / 2;
    // Adjust local coordinates by subtracting the offset
    final double adjustedY = localY - offsetY;
    // Convert to image coordinates using the actual scale
    final double result = adjustedY / actualScale;
    if (!result.isFinite) {
      return 0;
    }
    // Clamp to valid image bounds
    return result.clamp(0, _image.height - 1).toInt();
  }

  @override
  GestureTapDownCallback? get onSecondaryTapDown =>
      (final TapDownDetails details) {
        if (!_hasValidSize) {
          return;
        }
        _sendPort.match(
          () {},
          (final SendPort sendPort) => sendPort.send(
            RemoteFrameBufferIsolateSendMessage.pointerEvent(
              button1Down: false,
              button2Down: false,
              button3Down: true,
              button4Down: false,
              button5Down: false,
              button6Down: false,
              button7Down: false,
              button8Down: false,
              x: _toRemoteX(details.localPosition.dx),
              y: _toRemoteY(details.localPosition.dy),
            ),
          ),
        );
      };

  @override
  GestureTapUpCallback? get onSecondaryTapUp => (final TapUpDetails details) {
        if (!_hasValidSize) {
          return;
        }
        _sendPort.match(
          () {},
          (final SendPort sendPort) => sendPort.send(
            RemoteFrameBufferIsolateSendMessage.pointerEvent(
              button1Down: false,
              button2Down: false,
              button3Down: false,
              button4Down: false,
              button5Down: false,
              button6Down: false,
              button7Down: false,
              button8Down: false,
              x: _toRemoteX(details.localPosition.dx),
              y: _toRemoteY(details.localPosition.dy),
            ),
          ),
        );
      };

  @override
  GestureTapDownCallback? get onTapDown => (final TapDownDetails details) {
        if (!_hasValidSize) {
          return;
        }
        _sendPort.match(
          () {},
          (final SendPort sendPort) => sendPort.send(
            RemoteFrameBufferIsolateSendMessage.pointerEvent(
              button1Down: true,
              button2Down: false,
              button3Down: false,
              button4Down: false,
              button5Down: false,
              button6Down: false,
              button7Down: false,
              button8Down: false,
              x: _toRemoteX(details.localPosition.dx),
              y: _toRemoteY(details.localPosition.dy),
            ),
          ),
        );
      };

  @override
  GestureTapUpCallback? get onTapUp => (final TapUpDetails details) {
        if (!_hasValidSize) {
          return;
        }
        _sendPort.match(
          () {},
          (final SendPort sendPort) => sendPort.send(
            RemoteFrameBufferIsolateSendMessage.pointerEvent(
              button1Down: false,
              button2Down: false,
              button3Down: false,
              button4Down: false,
              button5Down: false,
              button6Down: false,
              button7Down: false,
              button8Down: false,
              x: _toRemoteX(details.localPosition.dx),
              y: _toRemoteY(details.localPosition.dy),
            ),
          ),
        );
      };
}

