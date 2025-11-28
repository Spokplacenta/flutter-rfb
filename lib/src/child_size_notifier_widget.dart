import 'package:flutter/widgets.dart';

/// Widget that exposes its child's size via a [ValueNotifier].
///
/// The size is updated whenever the widget is resized.
/// Inspired by: https://stackoverflow.com/a/58004112/373138
class SizeTrackingWidget extends StatefulWidget {
  final Widget _child;
  final ValueNotifier<Size> _sizeValueNotifier;

  const SizeTrackingWidget({
    super.key,
    required final ValueNotifier<Size> sizeValueNotifier,
    required final Widget child,
  })  : _child = child,
        _sizeValueNotifier = sizeValueNotifier;

  @override
  State<StatefulWidget> createState() => _SizeTackingState();
}

class _SizeTackingState extends State<SizeTrackingWidget> {
  Size? _lastSize;

  void _updateSize() {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final Size currentSize = renderBox.size;
      if (_lastSize != currentSize) {
        _lastSize = currentSize;
        widget._sizeValueNotifier.value = currentSize;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((final _) => _updateSize());
  }

  @override
  void didUpdateWidget(final SizeTrackingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((final _) => _updateSize());
  }

  @override
  Widget build(final BuildContext context) {
    // Use LayoutBuilder to detect size changes
    return LayoutBuilder(
      builder: (final BuildContext context, final BoxConstraints constraints) {
        // Schedule size update after layout
        WidgetsBinding.instance.addPostFrameCallback((final _) => _updateSize());
        return widget._child;
      },
    );
  }
}
