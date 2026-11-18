import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Image;
import 'package:fpdart/fpdart.dart' hide State;

/// A cursor shape received from the server, decoded into an [Image].
class RemoteFrameBufferCursorImage {
  /// The cursor, or none when the server hides it (a 0x0 cursor).
  final Option<Image> image;

  /// The point of the cursor at the pointer, in remote pixels.
  final int hotspotX;
  final int hotspotY;

  const RemoteFrameBufferCursorImage({
    required this.image,
    required this.hotspotX,
    required this.hotspotY,
  });

  void dispose() => image.match(() {}, (final Image image) => image.dispose());
}

/// Local feedback drawn over the framebuffer, without waiting for the server:
///
/// - the remote [cursor] at the mouse, at each frame, the system cursor being
///   hidden over the widget while a visible remote shape is drawn. Until a
///   shape arrives, or when the server sends an invisible one (0x0), the
///   [fallbackCursor] is shown instead, so the mouse never loses its
///   pointer. Nothing is drawn for touch or stylus input;
/// - with [pressFeedback], a halo at each press (mouse or touch) that fades
///   out in [pressFeedbackDuration].
///
/// The framebuffer of [frameBufferWidth] x [frameBufferHeight] pixels is
/// expected to be drawn by [child] with `BoxFit.contain`. Pointer events
/// still reach [child]: this widget only listens to them.
class RemoteFrameBufferLocalFeedback extends StatefulWidget {
  /// How long the halo of a press takes to fade out.
  static const Duration pressFeedbackDuration = Duration(milliseconds: 250);

  /// The radius of the halo on screen, in logical pixels, whatever the zoom.
  static const double pressFeedbackRadius = 20;

  final Widget child;
  final Option<RemoteFrameBufferCursorImage> cursor;

  /// The system cursor shown while no visible remote shape is drawn.
  final MouseCursor fallbackCursor;
  final int frameBufferHeight;
  final int frameBufferWidth;
  final bool pressFeedback;
  final Color pressFeedbackColor;

  const RemoteFrameBufferLocalFeedback({
    super.key,
    required this.child,
    required this.cursor,
    required this.fallbackCursor,
    required this.frameBufferHeight,
    required this.frameBufferWidth,
    required this.pressFeedback,
    required this.pressFeedbackColor,
  });

  @override
  State<RemoteFrameBufferLocalFeedback> createState() =>
      RemoteFrameBufferLocalFeedbackState();
}

@visibleForTesting
class RemoteFrameBufferLocalFeedbackState
    extends State<RemoteFrameBufferLocalFeedback>
    with SingleTickerProviderStateMixin {
  final _FeedbackModel _model = _FeedbackModel();

  /// Runs while halos fade out; created at the first press.
  Ticker? _ticker;

  /// Where the remote cursor is drawn, in local coordinates, if anywhere.
  @visibleForTesting
  Rect? get cursorRect => _model.cursorRect(_size);

  /// The number of halos being drawn.
  @visibleForTesting
  int get haloCount => _model.halos.length;

  Size get _size => context.size ?? Size.zero;

  @override
  Widget build(final BuildContext context) {
    _model
      ..cursor = widget.cursor
      ..color = widget.pressFeedbackColor
      ..frameBufferHeight = widget.frameBufferHeight
      ..frameBufferWidth = widget.frameBufferWidth;
    final bool drawsCursor = widget.cursor
        .flatMap((final RemoteFrameBufferCursorImage cursor) => cursor.image)
        .isSome();
    return MouseRegion(
      // Changing it while hovering takes effect at the next frame, without
      // the mouse leaving the widget.
      cursor: drawsCursor ? SystemMouseCursors.none : widget.fallbackCursor,
      onEnter: _trackMouse,
      onExit: (final _) => _model.setPointer(null),
      onHover: _trackMouse,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _trackMouse,
        child: Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _FeedbackPainter(_model)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(
    covariant final RemoteFrameBufferLocalFeedback oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (!widget.pressFeedback && _model.halos.isNotEmpty) {
      _model.halos.clear();
      _ticker?.stop();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _model.dispose();
    super.dispose();
  }

  void _onPointerDown(final PointerDownEvent event) {
    _trackMouse(event);
    if (!widget.pressFeedback) {
      return;
    }
    // Same size on screen inside an InteractiveViewer, whatever the zoom.
    final RenderObject? renderObject = context.findRenderObject();
    final double scale = renderObject is RenderBox && renderObject.attached
        ? renderObject.getTransformTo(null).getMaxScaleOnAxis()
        : 1;
    final Ticker ticker = _ticker ??= createTicker(_onTick);
    final Duration start = ticker.isActive ? _model.elapsed : Duration.zero;
    if (!ticker.isActive) {
      _model.elapsed = Duration.zero;
      unawaited(ticker.start());
    }
    _model.addHalo(
      _Halo(
        center: event.localPosition,
        radius: RemoteFrameBufferLocalFeedback.pressFeedbackRadius /
            (scale > 0 ? scale : 1),
        start: start,
      ),
    );
  }

  void _onTick(final Duration elapsed) {
    _model.elapsed = elapsed;
    _model.halos.removeWhere(
      (final _Halo halo) =>
          elapsed - halo.start >=
          RemoteFrameBufferLocalFeedback.pressFeedbackDuration,
    );
    if (_model.halos.isEmpty) {
      _ticker?.stop();
    }
    _model.repaint();
  }

  /// The local cursor follows the mouse only: touch and stylus hide it.
  void _trackMouse(final PointerEvent event) => _model.setPointer(
        event.kind == PointerDeviceKind.mouse ? event.localPosition : null,
      );
}

class _Halo {
  final Offset center;

  /// In local coordinates.
  final double radius;

  /// The ticker time of the press.
  final Duration start;

  const _Halo({
    required this.center,
    required this.radius,
    required this.start,
  });
}

/// What the painter draws; notifies to repaint without rebuilding.
class _FeedbackModel extends ChangeNotifier {
  Color color = const Color(0x00000000);
  Option<RemoteFrameBufferCursorImage> cursor = none();
  Duration elapsed = Duration.zero;
  int frameBufferHeight = 0;
  int frameBufferWidth = 0;
  final List<_Halo> halos = <_Halo>[];
  Offset? pointer;

  void addHalo(final _Halo halo) {
    halos.add(halo);
    notifyListeners();
  }

  /// The framebuffer area drawn with `BoxFit.contain` in [size], and the
  /// scale of one remote pixel.
  (Rect, double)? frameBufferRect(final Size size) {
    if (frameBufferWidth <= 0 ||
        frameBufferHeight <= 0 ||
        size.width <= 0 ||
        size.height <= 0) {
      return null;
    }
    final double scale = math.min(
      size.width / frameBufferWidth,
      size.height / frameBufferHeight,
    );
    final Size displayed =
        Size(frameBufferWidth * scale, frameBufferHeight * scale);
    return (
      Alignment.center.inscribe(displayed, Offset.zero & size),
      scale,
    );
  }

  /// Where the cursor is drawn in [size]: its hotspot at the pointer, one
  /// cursor pixel per remote pixel.
  Rect? cursorRect(final Size size) {
    final Offset? position = pointer;
    final (Rect, double)? area = frameBufferRect(size);
    if (position == null || area == null) {
      return null;
    }
    final double scale = area.$2;
    return cursor
        .flatMap(
          (final RemoteFrameBufferCursorImage cursor) => cursor.image.map(
            (final Image image) => Rect.fromLTWH(
              position.dx - cursor.hotspotX * scale,
              position.dy - cursor.hotspotY * scale,
              image.width * scale,
              image.height * scale,
            ),
          ),
        )
        .toNullable();
  }

  void repaint() => notifyListeners();

  void setPointer(final Offset? position) {
    if (position == pointer) {
      return;
    }
    pointer = position;
    if (cursor.isSome()) {
      notifyListeners();
    }
  }
}

class _FeedbackPainter extends CustomPainter {
  final _FeedbackModel model;

  _FeedbackPainter(this.model) : super(repaint: model);

  @override
  void paint(final Canvas canvas, final Size size) {
    for (final _Halo halo in model.halos) {
      final double t = ((model.elapsed - halo.start).inMicroseconds /
              RemoteFrameBufferLocalFeedback
                  .pressFeedbackDuration.inMicroseconds)
          .clamp(0.0, 1.0);
      // Translucent, fading out while it grows a little. The colour goes
      // through a filter so its own opacity is kept.
      canvas.drawCircle(
        halo.center,
        halo.radius * (0.6 + 0.4 * t),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.4 * (1 - t))
          ..colorFilter = ColorFilter.mode(model.color, BlendMode.srcIn),
      );
    }
    final Rect? cursorRect = model.cursorRect(size);
    final (Rect, double)? area = model.frameBufferRect(size);
    model.cursor
        .flatMap((final RemoteFrameBufferCursorImage c) => c.image)
        .match(
      () {},
      (final Image image) {
        if (cursorRect == null || area == null) {
          return;
        }
        canvas
          ..save()
          ..clipRect(area.$1)
          ..drawImageRect(
            image,
            Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
            cursorRect,
            Paint()..filterQuality = FilterQuality.low,
          )
          ..restore();
      },
    );
  }

  /// A rebuild brings a new cursor or colour; moves and halos repaint
  /// through [model] without one.
  @override
  bool shouldRepaint(covariant final _FeedbackPainter oldDelegate) => true;
}
