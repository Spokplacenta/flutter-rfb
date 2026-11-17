import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Image;
import 'package:flutter_rfb/src/extensions/coordinate_conversion_extensions.dart';
import 'package:flutter_rfb/src/remote_frame_buffer_isolate_messages.dart';
import 'package:fpdart/fpdart.dart' hide State;

/// Forwards pointer events to the remote server.
///
/// A [Listener] rather than a [GestureDetector]: it does not enter the gesture
/// arena, so a press is sent as soon as the pointer goes down, even inside an
/// `InteractiveViewer` (a tap recognizer only fires on release or after
/// `kPressTimeout` there). Moves with a button pressed are sent too, at most
/// one per frame (vsync). Only the first pointer is tracked: the other
/// fingers of a multi-touch gesture (e.g. a pinch) are not forwarded.
class RemoteFrameBufferPointerListener extends StatefulWidget {
  final Widget child;
  final Image image;
  final Size remoteFrameBufferWidgetSize;
  final Option<SendPort> sendPort;

  const RemoteFrameBufferPointerListener({
    super.key,
    required this.child,
    required this.image,
    required this.remoteFrameBufferWidgetSize,
    required this.sendPort,
  });

  @override
  State<RemoteFrameBufferPointerListener> createState() =>
      RemoteFrameBufferPointerListenerState();
}

@visibleForTesting
class RemoteFrameBufferPointerListenerState
    extends State<RemoteFrameBufferPointerListener> {
  /// The pointer currently forwarded, if any.
  int? _activePointer;

  /// The buttons of [_activePointer], as Flutter's bit mask.
  int _buttons = 0;

  /// The last move not sent yet, sent at the next frame.
  Offset? _pendingMove;

  bool _moveScheduled = false;

  @override
  Widget build(final BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerCancel: _onPointerCancel,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        child: widget.child,
      );

  /// Check if the widget and image sizes are valid for coordinate calculations.
  bool get _hasValidSize =>
      widget.remoteFrameBufferWidgetSize.width > 0 &&
      widget.remoteFrameBufferWidgetSize.height > 0 &&
      widget.image.width > 0 &&
      widget.image.height > 0;

  void _onPointerCancel(final PointerCancelEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    // Release whatever was pressed, so no button stays down on the server.
    _release(event.localPosition);
  }

  void _onPointerDown(final PointerDownEvent event) {
    if (_activePointer != null) {
      return;
    }
    _activePointer = event.pointer;
    // A touch or a stylus reports its contact as the primary button.
    _buttons = event.buttons == 0 ? kPrimaryButton : event.buttons;
    _pendingMove = null;
    _send(event.localPosition, _buttons);
  }

  void _onPointerMove(final PointerMoveEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    if (event.buttons != 0) {
      _buttons = event.buttons;
    }
    _pendingMove = event.localPosition;
    if (_moveScheduled) {
      return;
    }
    _moveScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((final _) {
      _moveScheduled = false;
      final Offset? position = _pendingMove;
      _pendingMove = null;
      if (!mounted || position == null || _activePointer == null) {
        return;
      }
      _send(position, _buttons);
    });
  }

  void _onPointerUp(final PointerUpEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    _release(event.localPosition);
  }

  void _release(final Offset position) {
    _activePointer = null;
    _buttons = 0;
    // The release carries the final position: a pending move is useless.
    _pendingMove = null;
    _send(position, 0);
  }

  /// Sends [buttons] (Flutter's bit mask) at [position] to the server.
  void _send(final Offset position, final int buttons) {
    if (!_hasValidSize) {
      return;
    }
    widget.sendPort.match(
      () {},
      (final SendPort sendPort) => sendPort.send(
        RemoteFrameBufferIsolateSendMessage.pointerEvent(
          // RFB buttons: 1 left, 2 middle, 3 right.
          button1Down: buttons & kPrimaryButton != 0,
          button2Down: buttons & kMiddleMouseButton != 0,
          button3Down: buttons & kSecondaryButton != 0,
          button4Down: false,
          button5Down: false,
          button6Down: false,
          button7Down: false,
          button8Down: false,
          x: position.dx.toRemoteX(
            widgetSize: widget.remoteFrameBufferWidgetSize,
            imageWidth: widget.image.width,
            imageHeight: widget.image.height,
          ),
          y: position.dy.toRemoteY(
            widgetSize: widget.remoteFrameBufferWidgetSize,
            imageWidth: widget.image.width,
            imageHeight: widget.image.height,
          ),
        ),
      ),
    );
  }
}
