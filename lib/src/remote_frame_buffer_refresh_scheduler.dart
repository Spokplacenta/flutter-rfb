import 'dart:async';

import 'package:dart_rfb/dart_rfb.dart';

/// Sends the non-incremental update requests that repaint the whole screen,
/// for servers that leave stale areas (e.g. Qt 4 QWS).
///
/// - With `fullRefreshInterval`, one request every `fullRefreshInterval`.
/// - With `refreshAfterChange`, one request `refreshAfterChange` after an
///   update covering at least [screenChangeRatio] of the screen (a screen
///   change). Another screen change before then pushes the request back.
///   A periodic refresh also stands for a pending one.
///
/// The update answering a refresh covers the whole screen, like a screen
/// change: it must not schedule another refresh, or refreshes would loop.
/// So after each refresh, the next screen change is taken as its answer and
/// ignored.
///
/// Without either duration, the scheduler does nothing. Call [dispose] when
/// the connection ends.
class RemoteFrameBufferRefreshScheduler {
  /// Creates a scheduler that calls [requestFullUpdate] for each refresh.
  /// [start] it once connected.
  RemoteFrameBufferRefreshScheduler({
    required final void Function() requestFullUpdate,
    final Duration? fullRefreshInterval,
    final Duration? refreshAfterChange,
  })  : _requestFullUpdate = requestFullUpdate,
        _fullRefreshInterval =
            checkDuration(fullRefreshInterval, 'fullRefreshInterval'),
        _refreshAfterChange =
            checkDuration(refreshAfterChange, 'refreshAfterChange');

  /// The part of the screen an update must cover to be a screen change.
  static const double screenChangeRatio = 0.2;

  final void Function() _requestFullUpdate;
  final Duration? _fullRefreshInterval;
  final Duration? _refreshAfterChange;

  Timer? _periodicTimer;
  Timer? _afterChangeTimer;
  bool _awaitingAnswer = false;
  bool _disposed = false;

  /// Returns [duration], which must be `null` or positive.
  static Duration? checkDuration(
    final Duration? duration,
    final String name,
  ) {
    if (duration != null && duration <= Duration.zero) {
      throw ArgumentError.value(duration, name, 'Must be positive');
    }
    return duration;
  }

  /// Whether a refresh is scheduled.
  bool get isActive =>
      (_periodicTimer?.isActive ?? false) ||
      (_afterChangeTimer?.isActive ?? false);

  /// Starts the periodic refresh, if any.
  void start() {
    final Duration? interval = _fullRefreshInterval;
    if (_disposed || interval == null || _periodicTimer != null) {
      return;
    }
    _periodicTimer = Timer.periodic(interval, (final _) => _refresh());
  }

  /// Handles an [update] of a [frameBufferWidth] x [frameBufferHeight]
  /// screen.
  void onUpdate({
    required final RemoteFrameBufferClientUpdate update,
    required final int frameBufferWidth,
    required final int frameBufferHeight,
  }) {
    final Duration? delay = _refreshAfterChange;
    if (_disposed ||
        delay == null ||
        !isScreenChange(
          update: update,
          frameBufferWidth: frameBufferWidth,
          frameBufferHeight: frameBufferHeight,
        )) {
      return;
    }
    if (_awaitingAnswer) {
      _awaitingAnswer = false;
      return;
    }
    _afterChangeTimer?.cancel();
    _afterChangeTimer = Timer(delay, _refresh);
  }

  /// Whether [update] covers at least [screenChangeRatio] of a
  /// [frameBufferWidth] x [frameBufferHeight] screen.
  static bool isScreenChange({
    required final RemoteFrameBufferClientUpdate update,
    required final int frameBufferWidth,
    required final int frameBufferHeight,
  }) {
    final int screen = frameBufferWidth * frameBufferHeight;
    if (screen <= 0) {
      return false;
    }
    final int covered = update.rectangles.fold(
      0,
      (final int sum, final RemoteFrameBufferClientUpdateRectangle rectangle) =>
          sum + rectangle.width * rectangle.height,
    );
    return covered >= screen * screenChangeRatio;
  }

  /// Cancels the scheduled refreshes, for good.
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    _afterChangeTimer?.cancel();
  }

  void _refresh() {
    if (_disposed) {
      return;
    }
    _afterChangeTimer?.cancel();
    _awaitingAnswer = _refreshAfterChange != null;
    _requestFullUpdate();
  }
}
