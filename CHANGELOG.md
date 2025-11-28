## 0.0.1

- Initial release

## 0.1.0

- Use dart_rfb 0.2.0
- Support for password authentication

## 0.2.0

- Support for pointer events
- Improved logging

## 0.3.0

- Add CopyRect encoding support

## 0.4.0

- Update `dart_rfb` to version 0.4.1 (hanging fix)
- Introduce `RemoteFrameBufferWidget.onError`
- Introduce `RemoteFrameBufferWidget.connectingWidget`

## 0.5.0

- Update `dart_rfb` to version 0.5.0 (key event support)
- Add key event support

## 0.6.0

- Update `dart_rfb` to version 0.6.0 (clipboard support)
- Add clipboard support

## 0.6.1

- Just a formatting fix

## 0.6.2

- Update `dart_rfb` to version 0.7.0 (refactored read loop)

## 0.7.0

- Use `dart_rfb` 0.9.0 with ZRLE support and widget-side logging

## 0.7.1

- Fix `Unsupported operation: Infinity or NaN toInt` error in gesture detector
- Add defensive checks for Infinity/NaN values in coordinate calculations

## 0.7.2

- Fix mouse pointer coordinate mapping to correctly handle different aspect ratios
- Fix coordinate calculation to account for BoxFit.contain scaling and centering offsets
- Fix widget size tracking to update correctly when window is resized
- Use ValueListenableBuilder to react to size changes in real-time
- Improve SizeTrackingWidget to use LayoutBuilder for accurate size updates
