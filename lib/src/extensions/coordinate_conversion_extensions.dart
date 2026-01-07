import 'dart:ui';

import 'package:flutter/widgets.dart' hide Image;

/// Extension to convert local widget coordinates to remote framebuffer coordinates.
///
/// With BoxFit.contain, the image is scaled to fit while preserving aspect ratio.
/// We need to calculate the actual scaling and offsets (centering) to map
/// widget coordinates to image coordinates correctly.
extension CoordinateConversion on double {
  /// Convert local X coordinate to remote framebuffer X coordinate.
  int toRemoteX({
    required final Size widgetSize,
    required final int imageWidth,
    required final int imageHeight,
  }) {
    // Check if sizes are valid
    if (widgetSize.width <= 0 ||
        widgetSize.height <= 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return 0;
    }
    // Additional defensive checks for Infinity/NaN
    if (!isFinite ||
        !widgetSize.width.isFinite ||
        !imageWidth.isFinite ||
        widgetSize.width == 0 ||
        imageWidth == 0) {
      return 0;
    }
    // Calculate scaling factors for both dimensions
    final double scaleX = widgetSize.width / imageWidth;
    final double scaleY = widgetSize.height / imageHeight;
    // With BoxFit.contain, the actual scale is the minimum to preserve aspect ratio
    final double actualScale = scaleX < scaleY ? scaleX : scaleY;
    // Calculate the displayed image size
    final double displayedWidth = imageWidth * actualScale;
    // Calculate offset (centering) - area where the image doesn't fill the widget horizontally
    final double offsetX = (widgetSize.width - displayedWidth) / 2;
    // Adjust local coordinates by subtracting the offset
    final double adjustedX = this - offsetX;
    // Convert to image coordinates using the actual scale
    final double result = adjustedX / actualScale;
    if (!result.isFinite) {
      return 0;
    }
    // Clamp to valid image bounds
    return result.clamp(0, imageWidth - 1).toInt();
  }

  /// Convert local Y coordinate to remote framebuffer Y coordinate.
  int toRemoteY({
    required final Size widgetSize,
    required final int imageWidth,
    required final int imageHeight,
  }) {
    // Check if sizes are valid
    if (widgetSize.width <= 0 ||
        widgetSize.height <= 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return 0;
    }
    // Additional defensive checks for Infinity/NaN
    if (!isFinite ||
        !widgetSize.height.isFinite ||
        !imageHeight.isFinite ||
        widgetSize.height == 0 ||
        imageHeight == 0) {
      return 0;
    }
    // Calculate scaling factors for both dimensions
    final double scaleX = widgetSize.width / imageWidth;
    final double scaleY = widgetSize.height / imageHeight;
    // With BoxFit.contain, the actual scale is the minimum to preserve aspect ratio
    final double actualScale = scaleX < scaleY ? scaleX : scaleY;
    // Calculate the displayed image size
    final double displayedHeight = imageHeight * actualScale;
    // Calculate offset (centering) - area where the image doesn't fill the widget vertically
    final double offsetY = (widgetSize.height - displayedHeight) / 2;
    // Adjust local coordinates by subtracting the offset
    final double adjustedY = this - offsetY;
    // Convert to image coordinates using the actual scale
    final double result = adjustedY / actualScale;
    if (!result.isFinite) {
      return 0;
    }
    // Clamp to valid image bounds
    return result.clamp(0, imageHeight - 1).toInt();
  }
}
